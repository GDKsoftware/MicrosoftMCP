unit MicrosoftMcp.Tools.OneDrive.Move;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.GraphId;

type
  TOneDriveMoveParams = class(TMicrosoftToolParams)
  private
    FPath: string;
    FNewParentId: string;
    FNewName: string;

  public
    [SchemaDescription('Path of the file or folder to move or rename, relative to the root of the OneDrive')]
    property Path: string read FPath write FPath;

    [Optional]
    [GraphId]
    [SchemaName('new_parent_id')]
    [SchemaDescription('Id of the folder to move the item to (the id of a folder from onedrive_list); empty keeps the current folder')]
    property NewParentId: string read FNewParentId write FNewParentId;

    [Optional]
    [SchemaName('new_name')]
    [SchemaDescription('New name of the item; empty keeps the current name')]
    property NewName: string read FNewName write FNewName;
  end;

  TOneDriveMoveTool = class(TMicrosoftTool<TOneDriveMoveParams, TFileActionResponse>)
  protected
    function Run(const Params: TOneDriveMoveParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse; override;

  public
    const ToolName = 'onedrive_move';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

const
  MovedStatus = 'moved';

resourcestring
  ToolDescription = 'Moves and/or renames a file or folder in the OneDrive of the account. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  NothingToDo = 'Give new_parent_id, new_name or both.';

{ TOneDriveMoveTool }

constructor TOneDriveMoveTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TOneDriveMoveTool.Run(const Params: TOneDriveMoveParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse;
begin
  TFilesSupport.GuardItemPath(Params.Path);

  const HasParent = not Params.NewParentId.Trim.IsEmpty;
  const HasName = not Params.NewName.Trim.IsEmpty;
  if not (HasParent or HasName) then
    raise EToolArgumentError.Create(NothingToDo);

  const Drive = FServices.GraphClients.CreateDrive(Mailbox);

  var ParentId := Params.NewParentId.Trim;
  var NewName := Params.NewName.Trim;

  // Graph needs both values in one request, so the one that is not given is taken from the item as it is now.
  if not (HasParent and HasName) then
  begin
    const Current = Drive.GetItem(Params.Path);
    if not HasParent then
      ParentId := Current.ParentId;

    if not HasName then
      NewName := Current.Name;
  end;

  const Moved = Drive.Move(Params.Path, ParentId, NewName);

  Result := TFileActionResponse.From(MovedStatus, Moved, TAccountSupport.Note(Mailbox));
end;

end.
