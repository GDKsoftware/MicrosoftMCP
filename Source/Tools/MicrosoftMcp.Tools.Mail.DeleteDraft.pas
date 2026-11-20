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

  TMailDeleteDraftTool = class(TMicrosoftTool<TMailDeleteDraftParams, TMailActionResponse>)
  protected
    function Run(const Params: TMailDeleteDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_delete_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Deletes a draft permanently. It cannot be used on a message that was sent; use mail_delete for that.';
  NotDeleted = 'The draft was not deleted.';
  DeletedStatus = 'deleted';

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
  const IsDeleted = TMailSupport.Client(Graph).DeleteDraft(Params.DraftId);
  if not IsDeleted then
    raise EToolError.Create(NotDeleted);

  Result := TMailActionResponse.Done(DeletedStatus);
end;

end.
