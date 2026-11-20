unit MicrosoftMcp.Tools.Mail.GetAttachment;

interface

uses
  System.Rtti,
  MCPServer.Types,
  MSGraph.Graph.Http,
  MSGraph.Graph.Mail.Interfaces,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.GraphId;

type
  TMailGetAttachmentParams = class(TMessageParams)
  private
    FAttachmentId: string;

  public
    [GraphId]
    [SchemaName('attachment_id')]
    [SchemaDescription('Id of the attachment, from mail_list_attachments')]
    property AttachmentId: string read FAttachmentId write FAttachmentId;
  end;

  // The content itself travels as an embedded resource; the structured content only describes it.
  TMailAttachmentInfo = class
  private
    FName: string;
    FContentType: string;
    FSize: Int64;

  public
    property Name: string read FName write FName;

    [SchemaName('content_type')]
    property ContentType: string read FContentType write FContentType;

    [SchemaDescription('Size in bytes')]
    property Size: Int64 read FSize write FSize;
  end;

  TMailGetAttachmentTool = class(TMicrosoftTool<TMailGetAttachmentParams, TMailAttachmentInfo>)
  private
    procedure GuardSize(const Mail: IMailClient; const Params: TMailGetAttachmentParams);

  protected
    function RunValue(const Params: TMailGetAttachmentParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue; override;

  public
    const ToolName = 'mail_get_attachment';
    const MaximumBytes = 10 * 1024 * 1024;

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  System.NetEncoding,
  System.JSON,
  MSGraph.Graph.Mail.Types,
  MCPServer.Tool.Result,
  MCPServer.Serializer,
  MicrosoftMcp.Tools.Exceptions,
  MicrosoftMcp.Tools.Mail.Support;

const
  UriFormat = 'mail-attachment:///%s';
  DefaultContentType = 'application/octet-stream';

resourcestring
  ToolDescription = 'Fetches one attachment of a message as an embedded resource (base64 content with its MIME type). ' +
                    'Attachments over 10 MB are refused.';
  TooLarge = 'The attachment "%s" is %d bytes; attachments over 10 MB cannot be fetched.';
  Described = 'Attachment "%s", %s, %d bytes.';

{ TMailGetAttachmentTool }

constructor TMailGetAttachmentTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TMailGetAttachmentTool.RunValue(const Params: TMailGetAttachmentParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TValue;
begin
  const Mail = TMailSupport.Client(Graph);
  GuardSize(Mail, Params);

  const Attachment = Mail.GetAttachmentContent(Params.MessageId, Params.AttachmentId);
  const Bytes = TNetEncoding.Base64String.DecodeStringToBytes(Attachment.ContentBytes);
  if Length(Bytes) > MaximumBytes then
    raise EToolError.CreateFmt(TooLarge, [Attachment.Name, Length(Bytes)]);

  var ContentType := Attachment.ContentType;
  if ContentType.IsEmpty then
    ContentType := DefaultContentType;

  const Info = TMailAttachmentInfo.Create;
  try
    Info.Name        := Attachment.Name;
    Info.ContentType := ContentType;
    Info.Size        := Length(Bytes);

    const Structured = TJSONObject.Create;
    TMCPSerializer.Serialize(Info, Structured);

    const Uri = Format(UriFormat, [TNetEncoding.URL.Encode(Attachment.Name)]);
    const ToolResult = TMCPToolResult.Create;
    ToolResult.AddText(Format(Described, [Attachment.Name, ContentType, Length(Bytes)]));
    ToolResult.AddEmbeddedBlob(Uri, ContentType, Bytes);
    ToolResult.SetStructuredContent(Structured);

    Result := TValue.From<TMCPToolResult>(ToolResult);
  finally
    Info.Free;
  end;
end;

procedure TMailGetAttachmentTool.GuardSize(const Mail: IMailClient; const Params: TMailGetAttachmentParams);
begin
  // The metadata is cheap; fetching the content of a large attachment is not, so the size is checked first.
  for var Attachment in Mail.GetMessageAttachments(Params.MessageId) do
  begin
    const IsRequested = (Attachment.Id = Params.AttachmentId);
    if IsRequested and (Attachment.Size > MaximumBytes) then
      raise EToolError.CreateFmt(TooLarge, [Attachment.Name, Attachment.Size]);
  end;
end;

end.
