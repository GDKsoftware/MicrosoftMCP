unit MicrosoftMcp.Tools.OneDrive.Upload;

interface

uses
  System.SysUtils,
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Files.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TOneDriveUploadParams = class(TMicrosoftToolParams)
  private
    FPath: string;
    FContent: string;
    FContentBase64: string;
    FOverwrite: Boolean;

  public
    [SchemaDescription('Path of the file to create, relative to the root of the OneDrive, for example Documents/notes.txt')]
    property Path: string read FPath write FPath;

    [Optional]
    [SchemaDescription('The content as text (stored as UTF-8). Give exactly one of content and content_base64')]
    property Content: string read FContent write FContent;

    [Optional]
    [SchemaName('content_base64')]
    [SchemaDescription('The content as base64, for binary files. Give exactly one of content and content_base64. At most 10 MB')]
    property ContentBase64: string read FContentBase64 write FContentBase64;

    [Optional]
    [SchemaDescription('True replaces an existing file with the same path; the default false fails when the file exists')]
    property Overwrite: Boolean read FOverwrite write FOverwrite;
  end;

  TOneDriveUploadTool = class(TMicrosoftTool<TOneDriveUploadParams, TFileActionResponse>)
  private
    function ContentOf(const Params: TOneDriveUploadParams): TBytes;
    function DecodeBase64(const ContentBase64: string): TBytes;

  protected
    function Run(const Params: TOneDriveUploadParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse; override;

  public
    const ToolName = 'onedrive_upload';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.NetEncoding,
  MSGraph.Graph.Drive.Types,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Account.Support,
  MicrosoftMcp.Tools.Files.Support;

const
  Base64BlockBytes = 3;
  Base64BlockChars = 4;
  UploadedStatus = 'uploaded';

resourcestring
  ToolDescription = 'Uploads a file to the OneDrive of the account, as text or as base64. Files over 10 MB are refused. ' +
                    'An existing file is only replaced when overwrite is true. ' +
                    'The mailbox only selects the account; a shared mailbox uses the account behind it.';
  BothContents = 'Give either content or content_base64, not both.';
  NoContent = 'Give the content of the file in content (text) or content_base64 (binary).';
  InvalidBase64 = 'content_base64 is not valid base64.';
  Base64TooLarge = 'The content in content_base64 is larger than 10 MB; files over 10 MB cannot be uploaded through this tool.';
  EmptyPath = 'Give the path of the file to create in path.';

{ TOneDriveUploadTool }

constructor TOneDriveUploadTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TOneDriveUploadTool.Run(const Params: TOneDriveUploadParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TFileActionResponse;
begin
  if Params.Path.Trim([' ', '/']).IsEmpty then
    raise EToolArgumentError.Create(EmptyPath);

  const Bytes = ContentOf(Params);
  TFilesSupport.GuardSize(Params.Path, Length(Bytes));

  var Mode := TGraphDriveWriteMode.FailIfExists;
  if Params.Overwrite then
    Mode := TGraphDriveWriteMode.Replace;

  const Drive = FServices.GraphClients.CreateDrive(Mailbox);
  const Uploaded = Drive.Upload(TGraphDriveUploadRequest.ForPath(Params.Path, Mode), Bytes);

  Result := TFileActionResponse.From(UploadedStatus, Uploaded, TAccountSupport.Note(Mailbox));
end;

function TOneDriveUploadTool.ContentOf(const Params: TOneDriveUploadParams): TBytes;
begin
  const HasText = not Params.Content.IsEmpty;
  const HasBase64 = not Params.ContentBase64.IsEmpty;

  if HasText and HasBase64 then
    raise EToolArgumentError.Create(BothContents);

  if not (HasText or HasBase64) then
    raise EToolArgumentError.Create(NoContent);

  if HasText then
    Result := TEncoding.UTF8.GetBytes(Params.Content)
  else
    Result := DecodeBase64(Params.ContentBase64);
end;

function TOneDriveUploadTool.DecodeBase64(const ContentBase64: string): TBytes;
begin
  // Checked on the text, so a huge string is refused before it is decoded.
  const MaximumChars = ((TFilesSupport.MaximumBytes + Base64BlockBytes - 1) div Base64BlockBytes) * Base64BlockChars;
  if Length(ContentBase64) > MaximumChars then
    raise EToolArgumentError.Create(Base64TooLarge);

  try
    Result := TNetEncoding.Base64String.DecodeStringToBytes(ContentBase64);
  except
    on EConvertError do
      raise EToolArgumentError.Create(InvalidBase64);
  end;
end;

end.
