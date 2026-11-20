unit MicrosoftMcp.Tools.OneDrive.CreateFolder;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TOneDriveCreateFolderParams = class(TMicrosoftToolParams)
  private
    FParentPath: string;
    FName: string;

  public
    [SchemaName('parent_path')]
    [SchemaDescription('Folder to create the new folder in, relative to the root of the OneDrive; / is the root')]
    property ParentPath: string read FParentPath write FParentPath;

    [SchemaDescription('Name of the new folder')]
    property Name: string read FName write FName;
  end;

  TOneDriveCreateFolderTool = class(TMicrosoftTool<TOneDriveCreateFolderParams, TFileActionResponse>)
  protected
    function Run(const Params: TOneDriveCreateFolderParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse; override;

  public
    const ToolName = 'onedrive_create_folder';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support;

const
  CreatedStatus = 'created';

resourcestring
  ToolDescription = 'Creates a folder in the OneDrive of the account. It fails when the name already exists. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  NameMissing = 'Give the name of the new folder in name.';

{ TOneDriveCreateFolderTool }

constructor TOneDriveCreateFolderTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TOneDriveCreateFolderTool.Run(const Params: TOneDriveCreateFolderParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse;
begin
  if Params.Name.Trim.IsEmpty then
    raise EToolArgumentError.Create(NameMissing);

  const Drive = FServices.GraphClients.CreateDrive(Mailbox);
  const Folder = Drive.CreateFolder(Params.ParentPath, Params.Name);

  Result := TFileActionResponse.From(CreatedStatus, Folder, TAccountSupport.Note(Mailbox));
end;

end.
