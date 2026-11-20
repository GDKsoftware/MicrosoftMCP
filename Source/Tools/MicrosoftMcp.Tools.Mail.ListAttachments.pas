unit MicrosoftMcp.Tools.Mail.ListAttachments;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MSGraph.Graph.Mail.Types,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailAttachmentItem = record
    Id: string;
    Name: string;

    [SchemaName('content_type')]
    ContentType: string;

    [SchemaDescription('Size in bytes')]
    Size: Int64;

    [SchemaName('is_inline')]
    IsInline: Boolean;

    class function FromAttachment(const Attachment: TMailAttachment): TMailAttachmentItem; static;
  end;

  TMailListAttachmentsResponse = class
  private
    FAttachments: TArray<TMailAttachmentItem>;

  public
    property Attachments: TArray<TMailAttachmentItem> read FAttachments write FAttachments;
  end;

  TMailListAttachmentsTool = class(TMicrosoftTool<TMessageParams, TMailListAttachmentsResponse>)
  protected
    function Run(const Params: TMessageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListAttachmentsResponse; override;

  public
    const ToolName = 'mail_list_attachments';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Lists the attachments of a message (id, name, type, size). Fetch one with mail_get_attachment.';

{ TMailAttachmentItem }

class function TMailAttachmentItem.FromAttachment(const Attachment: TMailAttachment): TMailAttachmentItem;
begin
  Result.Id          := Attachment.Id;
  Result.Name        := Attachment.Name;
  Result.ContentType := Attachment.ContentType;
  Result.Size        := Attachment.Size;
  Result.IsInline    := Attachment.IsInline;
end;

{ TMailListAttachmentsTool }

constructor TMailListAttachmentsTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TMailListAttachmentsTool.Run(const Params: TMessageParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailListAttachmentsResponse;
begin
  const Attachments = TMailSupport.Client(Graph).GetMessageAttachments(Params.MessageId);

  var Items: TArray<TMailAttachmentItem> := [];
  for var Attachment in Attachments do
  begin
    Items := Items + [TMailAttachmentItem.FromAttachment(Attachment)];
  end;

  Result := TMailListAttachmentsResponse.Create;
  Result.Attachments := Items;
end;

end.
