unit MicrosoftMcp.Tools.OneDrive.Delete;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TOneDriveDeleteParams = class(TConfirmableToolParams)
  private
    FPath: string;

  public
    [SchemaDescription('Path of the file or folder to delete, relative to the root of the OneDrive')]
    property Path: string read FPath write FPath;
  end;

  TOneDriveDeleteTool = class(TConfirmedMicrosoftTool<TOneDriveDeleteParams, TFileActionResponse>)
  protected
    function Summarize(const Params: TOneDriveDeleteParams; const Mailbox: TResolvedMailbox): string; override;
    function Run(const Params: TOneDriveDeleteParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse; override;

  public
    const ToolName = 'onedrive_delete';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Drive.Types,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

const
  DeletedStatus = 'deleted';
  FolderText = 'folder';
  FileText = 'file';
  WithNoteFormat = '%s %s';

resourcestring
  ToolDescription = 'Deletes a file or folder from the OneDrive of the account; it goes to the recycle bin. It needs confirmation: ' +
                    'the first call returns a summary and a confirmation_token. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  SummaryFormat = 'Delete the %s "%s" (%s) from the OneDrive of account %s. It goes to the recycle bin of that OneDrive.';

{ TOneDriveDeleteTool }

constructor TOneDriveDeleteTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TOneDriveDeleteTool.Summarize(const Params: TOneDriveDeleteParams; const Mailbox: TResolvedMailbox): string;
begin
  TFilesSupport.GuardItemPath(Params.Path);

  const Drive = FServices.GraphClients.CreateDrive(Mailbox);
  const Item = Drive.GetItem(Params.Path);

  var Kind := FileText;
  if Item.Kind = TGraphDriveItemKind.FolderItem then
    Kind := FolderText;

  Result := Format(SummaryFormat, [Kind, Item.Name, Params.Path, Mailbox.Account.UserName]);

  const Note = TAccountSupport.Note(Mailbox);
  if not Note.IsEmpty then
    Result := Format(WithNoteFormat, [Result, Note]);
end;

function TOneDriveDeleteTool.Run(const Params: TOneDriveDeleteParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse;
begin
  TFilesSupport.GuardItemPath(Params.Path);

  const Drive = FServices.GraphClients.CreateDrive(Mailbox);
  Drive.Delete(Params.Path);

  Result := TFileActionResponse.Done(DeletedStatus, Params.Path, TAccountSupport.Note(Mailbox));
end;

end.
