unit MicrosoftMcp.Tools.Mail.Forward;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailForwardParams = class(TConfirmedMessageParams)
  private
    FToRecipients: TArray<string>;
    FComment: string;

  public
    [SchemaName('to')]
    [SchemaDescription('E-mail addresses to forward the message to')]
    property ToRecipients: TArray<string> read FToRecipients write FToRecipients;

    [Optional]
    [SchemaDescription('Text to put above the forwarded message')]
    property Comment: string read FComment write FComment;
  end;

  TMailForwardTool = class(TConfirmedMicrosoftTool<TMailForwardParams, TMailActionResponse>)
  protected
    function Summarize(const Params: TMailForwardParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TMailForwardParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_forward';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Forwards a message to other people straight away. This reaches other people and cannot be undone, so it needs confirmation: ' +
                    'the first call returns a summary and a confirmation_token. To review the text first, use mail_create_forward_draft.';
  SummaryFormat = 'Forward the message with subject "%s" from mailbox %s to %s.';
  NotForwarded = 'The message was not forwarded.';
  ForwardedStatus = 'forwarded';

{ TMailForwardTool }

constructor TMailForwardTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TMailForwardTool.Summarize(const Params: TMailForwardParams; const Mailbox: TResolvedMailbox): string;
begin
  TMailSupport.RequireRecipients(Params.ToRecipients);

  const Original = TMailSupport.LoadMessage(FServices.GraphClients, Mailbox, Params.MessageId);
  const Recipients = TMailSupport.RecipientsText(Params.ToRecipients, nil, nil);

  Result := Format(SummaryFormat, [Original.Subject, TMailSupport.MailboxLabel(Mailbox), Recipients]);
end;

function TMailForwardTool.Run(const Params: TMailForwardParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse;
begin
  const Recipients = TMailSupport.RequireRecipients(Params.ToRecipients);

  const IsForwarded = TMailSupport.Client(Graph).ForwardMessage(Params.MessageId, Params.Comment, Recipients);
  if not IsForwarded then
    raise EToolError.Create(NotForwarded);

  Result := TMailActionResponse.Done(ForwardedStatus);
end;

end.
