unit MicrosoftMcp.Tools.OneDrive.Read;

interface

uses
  System.Rtti,
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TOneDrivePathParams = class(TMicrosoftToolParams)
  private
    FPath: string;

  public
    [SchemaDescription('Path of the file or folder, relative to the root of the OneDrive, for example Documents/notes.txt')]
    property Path: string read FPath write FPath;
  end;

  // The content itself is a text block or an embedded resource; the structured content only describes it.
  TOneDriveReadTool = class(TMicrosoftTool<TOneDrivePathParams, TFileReadInfo>)
  protected
    function RunValue(const Params: TOneDrivePathParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue; override;

  public
    const ToolName = 'onedrive_read';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Drive.Types,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

resourcestring
  ToolDescription = 'Reads a file of the OneDrive of the account: text files come back as text, other files (Word, Excel, PDF, images) as an ' +
                    'embedded resource with their MIME type. Files over 10 MB are refused. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  IsFolder = 'The item "%s" is a folder; list it with onedrive_list and read one of its files.';
  NoDownloadUrl = 'Microsoft Graph gave no download link for "%s"; it may not be a file with content.';

{ TOneDriveReadTool }

constructor TOneDriveReadTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TOneDriveReadTool.RunValue(const Params: TOneDrivePathParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue;
begin
  const Drive = FServices.GraphClients.CreateDrive(Mailbox);

  const Item = Drive.GetItem(Params.Path);
  if Item.Kind = TGraphDriveItemKind.FolderItem then
    raise EToolError.CreateFmt(IsFolder, [Item.Name]);

  // The metadata is cheap; fetching the content of a large file is not, so the size is checked first.
  TFilesSupport.GuardSize(Item.Name, Item.Size);

  if Item.DownloadUrl.IsEmpty then
    raise EToolError.CreateFmt(NoDownloadUrl, [Item.Name]);

  const Bytes = Drive.DownloadContent(Item.DownloadUrl);
  TFilesSupport.GuardSize(Item.Name, Length(Bytes));

  const Entry = TFileEntry.FromGraphItem(Item);
  Result := TFilesSupport.ReadResult(Item.Name, Entry.MimeType, Bytes, TAccountSupport.Note(Mailbox));
end;

end.
