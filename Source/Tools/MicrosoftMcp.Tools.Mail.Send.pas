unit MicrosoftMcp.Tools.Mail.Send;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailSendParams = class(TConfirmableToolParams)
  private
    FToRecipients: TArray<string>;
    FCcRecipients: TArray<string>;
    FBccRecipients: TArray<string>;
    FSubject: string;
    FBody: string;
    FBodyType: string;

  public
    [SchemaName('to')]
    [SchemaDescription('E-mail addresses of the recipients')]
    property ToRecipients: TArray<string> read FToRecipients write FToRecipients;

    [Optional]
    [SchemaName('cc')]
    property CcRecipients: TArray<string> read FCcRecipients write FCcRecipients;

    [Optional]
    [SchemaName('bcc')]
    property BccRecipients: TArray<string> read FBccRecipients write FBccRecipients;

    property Subject: string read FSubject write FSubject;

    [SchemaDescription('Body of the message; the signature of the mailbox is added')]
    property Body: string read FBody write FBody;

    [Optional]
    [SchemaName('body_type')]
    [SchemaEnum('text', 'html')]
    [SchemaDescription('text (default) or html')]
    property BodyType: string read FBodyType write FBodyType;
  end;

  TMailSendTool = class(TConfirmedMicrosoftTool<TMailSendParams, TMailActionResponse>)
  protected
    function Summarize(const Params: TMailSendParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TMailSendParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_send';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Writes and sends a message in one step. This reaches other people and cannot be undone, so it needs confirmation: ' +
                    'the first call returns a summary and a confirmation_token. To let the user review the text first, use mail_create_draft.';
  SummaryFormat = 'Send an e-mail with subject "%s" from mailbox %s to %s.';
  NotSent = 'The message was created as a draft (id %s) but could not be sent: %s';
  SentStatus = 'sent';
  SendRefused = 'Microsoft Graph did not accept the send request';

{ TMailSendTool }

constructor TMailSendTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TMailSendTool.Summarize(const Params: TMailSendParams; const Mailbox: TResolvedMailbox): string;
begin
  TMailSupport.RequireRecipients(Params.ToRecipients);

  const Recipients = TMailSupport.RecipientsText(Params.ToRecipients, Params.CcRecipients, Params.BccRecipients);
  Result := Format(SummaryFormat, [Params.Subject, TMailSupport.MailboxLabel(Mailbox), Recipients]);
end;

function TMailSendTool.Run(const Params: TMailSendParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse;
begin
  const IsHtml = SameText(Params.BodyType, TMailSupport.HtmlBodyType);
  const Mail = TMailSupport.Client(Graph);

  const Draft = Mail.CreateDraft(Params.Subject, Params.Body,
                                 TMailSupport.RequireRecipients(Params.ToRecipients),
                                 TMailSupport.CleanRecipients(Params.CcRecipients),
                                 TMailSupport.CleanRecipients(Params.BccRecipients),
                                 IsHtml);

  // The draft stays in the Drafts folder when sending fails, so the message is not lost.
  try
    const IsSent = Mail.SendDraft(Draft.Id);
    if not IsSent then
      raise EToolError.CreateFmt(NotSent, [Draft.Id, SendRefused]);
  except
    on E: EToolError do
      raise;
    on E: Exception do
      raise EToolError.CreateFmt(NotSent, [Draft.Id, FServices.Errors.Translate(E, Mailbox.Mailbox)]);
  end;

  Result := TMailActionResponse.Done(SentStatus);
end;

end.
