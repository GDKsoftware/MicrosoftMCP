unit MicrosoftMcp.Tools.OneDrive.List;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TOneDriveListParams = class(TMicrosoftToolParams)
  private
    FPath: string;

  public
    [Optional]
    [SchemaDescription('Folder to list, relative to the root of the OneDrive, for example Documents/Reports. / or empty is the root')]
    property Path: string read FPath write FPath;
  end;

  TOneDriveListTool = class(TMicrosoftTool<TOneDriveListParams, TFileListResponse>)
  protected
    function Run(const Params: TOneDriveListParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileListResponse; override;

  public
    const ToolName = 'onedrive_list';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Account.Support;

resourcestring
  ToolDescription = 'Lists the files and folders of a folder in the OneDrive of the account (first page). ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';

{ TOneDriveListTool }

constructor TOneDriveListTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TOneDriveListTool.Run(const Params: TOneDriveListParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileListResponse;
begin
  const Drive = FServices.GraphClients.CreateDrive(Mailbox);
  const Page = Drive.ListChildren(Params.Path);

  var Entries: TArray<TFileEntry> := [];
  for var Item in Page.Items do
  begin
    Entries := Entries + [TFileEntry.FromGraphItem(Item)];
  end;

  Result := TFileListResponse.From(Entries, Page.HasMore, TAccountSupport.Note(Mailbox));
end;

end.
