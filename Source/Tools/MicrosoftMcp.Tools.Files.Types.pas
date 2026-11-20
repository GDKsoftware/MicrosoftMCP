unit MicrosoftMcp.Tools.Files.Types;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.SharePoint.Types,
  MSGraph.Graph.Drive.Types;

type
  // A file or folder as the SharePoint and OneDrive tools list it.
  TFileEntry = record
    Id: string;
    Name: string;

    [SchemaName('type')]
    [SchemaDescription('file or folder')]
    EntryType: string;

    [SchemaDescription('Size in bytes')]
    Size: Int64;

    [SchemaName('mime_type')]
    MimeType: string;

    [SchemaName('web_url')]
    WebUrl: string;

    [SchemaName('last_modified')]
    LastModified: string;

    class function FromDriveItem(const Item: TDriveItem): TFileEntry; static;
    class function FromGraphItem(const Item: TGraphDriveItem): TFileEntry; static;
  end;

  TFileListResponse = class
  private
    FItems: TArray<TFileEntry>;
    FHasMore: Boolean;
    FNote: string;

  public
    property Items: TArray<TFileEntry> read FItems write FItems;

    [SchemaName('has_more')]
    [SchemaDescription('True when the folder holds more items than this answer lists')]
    property HasMore: Boolean read FHasMore write FHasMore;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;

    class function From(const Items: TArray<TFileEntry>; const HasMore: Boolean; const Note: string): TFileListResponse; static;
  end;

  // The structured part of a file read; the content itself is a text block or an embedded resource.
  TFileReadInfo = class
  private
    FName: string;
    FContentType: string;
    FSize: Int64;
    FIsText: Boolean;
    FNote: string;

  public
    property Name: string read FName write FName;

    [SchemaName('content_type')]
    property ContentType: string read FContentType write FContentType;

    [SchemaDescription('Size in bytes')]
    property Size: Int64 read FSize write FSize;

    [SchemaName('is_text')]
    [SchemaDescription('True when the content came as text, false when it came as an embedded resource')]
    property IsText: Boolean read FIsText write FIsText;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;
  end;

  TFileActionResponse = class
  private
    FStatus: string;
    FItemId: string;
    FName: string;
    FSize: Int64;
    FWebUrl: string;
    FNote: string;

  public
    property Status: string read FStatus write FStatus;

    [SchemaName('item_id')]
    property ItemId: string read FItemId write FItemId;

    property Name: string read FName write FName;
    property Size: Int64 read FSize write FSize;

    [SchemaName('web_url')]
    property WebUrl: string read FWebUrl write FWebUrl;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;

    class function From(const Status: string; const Item: TGraphDriveItem; const Note: string): TFileActionResponse; static;
    class function Done(const Status, Name, Note: string): TFileActionResponse; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

const
  FileType = 'file';
  FolderType = 'folder';
  FileMember = 'file';
  MimeTypeMember = 'mimeType';
  WebUrlMember = 'webUrl';

{ TFileEntry }

class function TFileEntry.FromDriveItem(const Item: TDriveItem): TFileEntry;
begin
  Result.Id           := Item.Id;
  Result.Name         := Item.Name;
  Result.EntryType    := Item.ItemType;
  Result.Size         := Item.Size;
  Result.MimeType     := Item.MimeType;
  Result.WebUrl       := Item.WebUrl;
  Result.LastModified := Item.LastModifiedDateTime;
end;

class function TFileEntry.FromGraphItem(const Item: TGraphDriveItem): TFileEntry;
begin
  Result.Id           := Item.Id;
  Result.Name         := Item.Name;
  Result.Size         := Item.Size;
  Result.LastModified := Item.LastModified;
  Result.MimeType     := '';
  Result.WebUrl       := '';

  case Item.Kind of
    TGraphDriveItemKind.FileItem   : Result.EntryType := FileType;
    TGraphDriveItemKind.FolderItem : Result.EntryType := FolderType;
  else
    Result.EntryType := '';
  end;

  // The mapped item keeps only what the drive client needs; the rest is in the raw JSON.
  const Raw = TJSONObject.ParseJSONValue(Item.Raw);
  try
    const IsObject = (Raw is TJSONObject);
    if not IsObject then
      Exit;

    TJSONObject(Raw).TryGetValue<string>(WebUrlMember, Result.WebUrl);

    var FileObject: TJSONObject := nil;
    const HasFileFacet = TJSONObject(Raw).TryGetValue<TJSONObject>(FileMember, FileObject);
    if HasFileFacet then
      FileObject.TryGetValue<string>(MimeTypeMember, Result.MimeType);
  finally
    Raw.Free;
  end;
end;

{ TFileListResponse }

class function TFileListResponse.From(const Items: TArray<TFileEntry>; const HasMore: Boolean; const Note: string): TFileListResponse;
begin
  Result := TFileListResponse.Create;

  Result.Items := Items;
  Result.HasMore := HasMore;
  Result.Note := Note;
end;

{ TFileActionResponse }

class function TFileActionResponse.From(const Status: string; const Item: TGraphDriveItem; const Note: string): TFileActionResponse;
begin
  Result := TFileActionResponse.Create;

  Result.Status := Status;
  Result.ItemId := Item.Id;
  Result.Name   := Item.Name;
  Result.Size   := Item.Size;
  Result.Note   := Note;

  const Entry = TFileEntry.FromGraphItem(Item);
  Result.WebUrl := Entry.WebUrl;
end;

class function TFileActionResponse.Done(const Status, Name, Note: string): TFileActionResponse;
begin
  Result := TFileActionResponse.Create;

  Result.Status := Status;
  Result.Name   := Name;
  Result.Note   := Note;
end;

end.
