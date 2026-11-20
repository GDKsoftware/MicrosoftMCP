unit MicrosoftMcp.Tools.Mail.Move;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailMoveParams = class(TMessageParams)
  private
    FDestinationFolder: string;

  public
    [SchemaName('destination_folder')]
    [SchemaDescription('inbox, archive, deleteditems, junkemail, drafts, sentitems, or a folder id from mail_list_folders')]
    property DestinationFolder: string read FDestinationFolder write FDestinationFolder;
  end;

  TMailMoveResponse = class
  private
    FMessageId: string;

  public
    [SchemaName('message_id')]
    [SchemaDescription('The message gets a new id in the destination folder')]
    property MessageId: string read FMessageId write FMessageId;
  end;

  TMailMoveTool = class(TMicrosoftTool<TMailMoveParams, TMailMoveResponse>)
  protected
    function Run(const Params: TMailMoveParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailMoveResponse; override;

  public
    const ToolName = 'mail_move';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

const
  DeletedItemsFolder = 'deleteditems';

resourcestring
  ToolDescription = 'Moves a message to another folder of the same mailbox. The message gets a new id. ' +
                    'To delete a message use mail_delete, not a move to deleteditems.';
  UseMailDelete = 'Moving a message to Deleted Items deletes it; use mail_delete, which asks the user to confirm.';

{ TMailMoveTool }

constructor TMailMoveTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailMoveTool.Run(const Params: TMailMoveParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailMoveResponse;
begin
  const FolderId = TMailSupport.FolderId(Params.DestinationFolder);
  if SameText(FolderId, DeletedItemsFolder) then
    raise EToolArgumentError.Create(UseMailDelete);

  const Moved = TMailSupport.Client(Graph).MoveMessage(Params.MessageId, FolderId);

  Result := TMailMoveResponse.Create;
  Result.MessageId := Moved.NewMessageId;
end;

end.
