unit MicrosoftMcp.Tools.Mail.SendDraft;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.GraphId;

type
  TMailSendDraftParams = class(TConfirmableToolParams)
  private
    FDraftId: string;

  public
    [GraphId]
    [SchemaName('draft_id')]
    [SchemaDescription('Id of the draft, from mail_create_draft or one of the reply and forward draft tools')]
    property DraftId: string read FDraftId write FDraftId;
  end;

  TMailSendDraftTool = class(TConfirmedMicrosoftTool<TMailSendDraftParams, TMailActionResponse>)
  protected
    function Summarize(const Params: TMailSendDraftParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TMailSendDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_send_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Sends an existing draft. This reaches other people and cannot be undone, so it needs confirmation: ' +
                    'the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Send the draft with subject "%s" from mailbox %s to %s.';
  NotSent = 'The draft was not sent.';
  SentStatus = 'sent';

{ TMailSendDraftTool }

constructor TMailSendDraftTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TMailSendDraftTool.Summarize(const Params: TMailSendDraftParams; const Mailbox: TResolvedMailbox): string;
begin
  const Draft = TMailSupport.LoadMessage(FServices.GraphClients, Mailbox, Params.DraftId);

  const Recipients = TMailSupport.FormatAddresses(Draft.ToRecipients);
  Result := Format(SummaryFormat, [Draft.Subject, TMailSupport.MailboxLabel(Mailbox), Recipients]);
end;

function TMailSendDraftTool.Run(const Params: TMailSendDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse;
begin
  const IsSent = TMailSupport.Client(Graph).SendDraft(Params.DraftId);
  if not IsSent then
    raise EToolError.Create(NotSent);

  Result := TMailActionResponse.Done(SentStatus);
end;

end.
