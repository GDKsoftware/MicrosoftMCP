unit MicrosoftMcp.Tools.Mail.DeleteDraft;

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
  TMailDeleteDraftParams = class(TMicrosoftToolParams)
  private
    FDraftId: string;

  public
    [GraphId]
    [SchemaName('draft_id')]
    [SchemaDescription('Id of the draft, from mail_create_draft')]
    property DraftId: string read FDraftId write FDraftId;
  end;

  // Deletes without confirmation, so it first checks that the message is a draft: a DELETE in Graph removes any
  // message for good, while mail_delete moves one to Deleted Items after a confirmation.
  TMailDeleteDraftTool = class(TMicrosoftTool<TMailDeleteDraftParams, TMailActionResponse>)
  private
    procedure GuardIsDraft(const Graph: TGraphHttpClient; const MessageId: string);

  protected
    function Run(const Params: TMailDeleteDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_delete_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.JSON,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Deletes a draft permanently. Any message that is not a draft is refused; use mail_delete for those.';
  NotDeleted = 'The draft was not deleted.';
  DeletedStatus = 'deleted';
  NotADraft = 'This message is not a draft, so mail_delete_draft does not delete it. Use mail_delete, which moves it to ' +
              'Deleted Items after the user confirmed.';

const
  IsDraftField = 'isDraft';

{ TMailDeleteDraftTool }

constructor TMailDeleteDraftTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TMailDeleteDraftTool.Run(const Params: TMailDeleteDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse;
begin
  GuardIsDraft(Graph, Params.DraftId);

  const IsDeleted = TMailSupport.Client(Graph).DeleteDraft(Params.DraftId);
  if not IsDeleted then
    raise EToolError.Create(NotDeleted);

  Result := TMailActionResponse.Done(DeletedStatus);
end;

procedure TMailDeleteDraftTool.GuardIsDraft(const Graph: TGraphHttpClient; const MessageId: string);
begin
  const Message = TMailSupport.ReadMessageFields(Graph, MessageId, IsDraftField);
  try
    const IsDraft = Message.GetValue<Boolean>(IsDraftField, False);
    if not IsDraft then
      raise EToolArgumentError.Create(NotADraft);
  finally
    Message.Free;
  end;
end;

end.
