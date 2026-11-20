unit MicrosoftMcp.Tools.Files.Support;

interface

uses
  System.SysUtils,
  System.Rtti,
  MSGraph.Graph.Http,
  MSGraph.Graph.SharePoint.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces;

type
  // Helpers the SharePoint and OneDrive tools share: the 10 MB rule, text detection and the answer of a file read.
  TFilesSupport = class
  private
    class function HasTextMimeType(const MimeType: string): Boolean; static;
    class function HasTextExtension(const Name: string): Boolean; static;
    class function HasNulByte(const Bytes: TBytes): Boolean; static;
    class function DecodeText(const Bytes: TBytes): string; static;

  public
    const MaximumBytes = 10 * 1024 * 1024;

    class function SharePointClient(const Graph: TGraphHttpClient): ISharePointClient; static;

    // Raises a clear error when the content is larger than MaximumBytes; called before the content is fetched.
    class procedure GuardSize(const Name: string; const Size: Int64); static;

    // Text (UTF-8) when the MIME type or the extension says so and the bytes hold no NUL; everything else is binary.
    // Office formats are binary: Graph's format conversion is not used.
    class function IsText(const MimeType, Name: string; const Bytes: TBytes): Boolean; static;

    // Text goes into a text block, anything else into an embedded resource; the structured content describes both.
    class function ReadResult(const Name, MimeType: string; const Bytes: TBytes; const Note: string): TValue; static;
  end;

implementation

uses
  System.NetEncoding,
  System.JSON,
  MCPServer.Tool.Result,
  MCPServer.Serializer,
  MSGraph.Graph.SharePoint,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Files.Types;

const
  DefaultContentType = 'application/octet-stream';
  UriFormat = 'file-content:///%s';
  TextPrefix = 'text/';
  TextMimeTypes: array[0..8] of string = ('application/json', 'application/xml', 'application/javascript', 'application/x-yaml',
                                           'application/yaml', 'application/sql', 'application/x-sh', 'application/x-www-form-urlencoded',
                                           'application/ecmascript');
  TextSuffixes: array[0..1] of string = ('+json', '+xml');
  TextExtensions: array[0..39] of string = ('.txt', '.md', '.markdown', '.csv', '.tsv', '.json', '.xml', '.html', '.htm', '.css', '.js', '.mjs', '.ts',
                                            '.yaml', '.yml', '.ini', '.log', '.sql', '.sh', '.ps1', '.bat', '.cmd', '.cfg', '.conf', '.toml',
                                            '.svg', '.py', '.pas', '.dpr', '.dfm', '.cs', '.java', '.c', '.cpp', '.h', '.go', '.rs', '.php',
                                            '.ics', '.eml');
  ByteOrderMark = #$FEFF;
  HeaderWithNoteFormat = '%s%s%s';

resourcestring
  TooLarge = 'The file "%s" is %d bytes; files over 10 MB cannot be read or uploaded through this tool.';
  Described = 'File "%s", %s, %d bytes, as %s.';
  AsText = 'text';
  AsResource = 'an embedded resource';

{ TFilesSupport }

class function TFilesSupport.SharePointClient(const Graph: TGraphHttpClient): ISharePointClient;
begin
  Result := TSharePointClient.Create(Graph, False);
end;

class procedure TFilesSupport.GuardSize(const Name: string; const Size: Int64);
begin
  if Size > MaximumBytes then
    raise EToolError.CreateFmt(TooLarge, [Name, Size]);
end;

class function TFilesSupport.IsText(const MimeType, Name: string; const Bytes: TBytes): Boolean;
begin
  const SaysText = (HasTextMimeType(MimeType) or HasTextExtension(Name));

  Result := (SaysText and not HasNulByte(Bytes));
end;

class function TFilesSupport.HasTextMimeType(const MimeType: string): Boolean;
begin
  const BareType = MimeType.Split([';'])[0].Trim.ToLower;
  if BareType.StartsWith(TextPrefix) then
    Exit(True);

  for var TextType in TextMimeTypes do
  begin
    if BareType = TextType then
      Exit(True);
  end;

  for var Suffix in TextSuffixes do
  begin
    if BareType.EndsWith(Suffix) then
      Exit(True);
  end;

  Result := False;
end;

class function TFilesSupport.HasTextExtension(const Name: string): Boolean;
begin
  const Lowered = Name.ToLower;

  for var Extension in TextExtensions do
  begin
    if Lowered.EndsWith(Extension) then
      Exit(True);
  end;

  Result := False;
end;

class function TFilesSupport.HasNulByte(const Bytes: TBytes): Boolean;
begin
  for var Value in Bytes do
  begin
    if Value = 0 then
      Exit(True);
  end;

  Result := False;
end;

class function TFilesSupport.DecodeText(const Bytes: TBytes): string;
begin
  Result := TEncoding.UTF8.GetString(Bytes);

  const HasMark = Result.StartsWith(ByteOrderMark);
  if HasMark then
    Result := Result.Substring(1);
end;

class function TFilesSupport.ReadResult(const Name, MimeType: string; const Bytes: TBytes; const Note: string): TValue;
begin
  var ContentType := MimeType;
  if ContentType.IsEmpty then
    ContentType := DefaultContentType;

  const IsTextContent = IsText(MimeType, Name, Bytes);

  const Info = TFileReadInfo.Create;
  try
    Info.Name        := Name;
    Info.ContentType := ContentType;
    Info.Size        := Length(Bytes);
    Info.IsText      := IsTextContent;
    Info.Note        := Note;

    const Structured = TJSONObject.Create;
    TMCPSerializer.Serialize(Info, Structured);

    var Kind := AsResource;
    if IsTextContent then
      Kind := AsText;

    var Header := Format(Described, [Name, ContentType, Length(Bytes), Kind]);
    if not Note.IsEmpty then
      Header := Format(HeaderWithNoteFormat, [Header, sLineBreak, Note]);

    const ToolResult = TMCPToolResult.Create;
    ToolResult.AddText(Header);

    if IsTextContent then
      ToolResult.AddText(DecodeText(Bytes))
    else
      ToolResult.AddEmbeddedBlob(Format(UriFormat, [TNetEncoding.URL.Encode(Name)]), ContentType, Bytes);

    ToolResult.SetStructuredContent(Structured);

    Result := TValue.From<TMCPToolResult>(ToolResult);
  finally
    Info.Free;
  end;
end;

end.
