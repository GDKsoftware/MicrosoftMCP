unit MicrosoftMcp.Tools.Mail.Delete;

interface

uses
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailDeleteTool = class(TConfirmedMicrosoftTool<TConfirmedMessageParams, TMailActionResponse>)
  protected
    function Summarize(const Params: TConfirmedMessageParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TConfirmedMessageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_delete';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Mail.Support;

const
  DeletedItemsFolder = 'deleteditems';

resourcestring
  ToolDescription = 'Deletes a message by moving it to the Deleted Items folder of its mailbox. It needs confirmation: ' +
                    'the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Delete the message with subject "%s" from %s in mailbox %s (it moves to Deleted Items).';
  DeletedStatus = 'moved to Deleted Items';

{ TMailDeleteTool }

constructor TMailDeleteTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TMailDeleteTool.Summarize(const Params: TConfirmedMessageParams; const Mailbox: TResolvedMailbox): string;
begin
  const Message = TMailSupport.LoadMessage(FServices.GraphClients, Mailbox, Params.MessageId);

  Result := Format(SummaryFormat, [Message.Subject, TMailSupport.FormatAddress(Message.From), TMailSupport.MailboxLabel(Mailbox)]);
end;

function TMailDeleteTool.Run(const Params: TConfirmedMessageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse;
begin
  TMailSupport.Client(Graph).MoveMessage(Params.MessageId, DeletedItemsFolder);

  Result := TMailActionResponse.Done(DeletedStatus);
end;

end.
