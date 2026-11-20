unit MicrosoftMcp.Tools.Mail.Types;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Mail.Types,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.GraphId;

type
  // A message as the list tools show it: never the body, only the preview.
  TMessageListItem = record
    Id: string;
    Subject: string;

    [SchemaName('from')]
    Sender: string;

    Received: string;

    [SchemaName('is_read')]
    IsRead: Boolean;

    [SchemaName('has_attachments')]
    HasAttachments: Boolean;

    Preview: string;

    class function FromMessage(const Message: TMailMessage): TMessageListItem; static;
  end;

  TMailListResponse = class
  private
    FMessages: TArray<TMessageListItem>;
    FHasMore: Boolean;

  public
    property Messages: TArray<TMessageListItem> read FMessages write FMessages;

    [SchemaName('has_more')]
    property HasMore: Boolean read FHasMore write FHasMore;

    class function FromResult(const SearchResult: TSearchMessagesResult): TMailListResponse; static;
  end;

  TMailDraftResponse = class
  private
    FDraftId: string;
    FSubject: string;

  public
    [SchemaName('draft_id')]
    [SchemaDescription('Id of the draft; pass it to mail_update_draft, mail_send_draft or mail_delete_draft')]
    property DraftId: string read FDraftId write FDraftId;

    property Subject: string read FSubject write FSubject;

    class function FromDraft(const Draft: TDraftResult): TMailDraftResponse; static;
  end;

  TMailActionResponse = class
  private
    FStatus: string;

  public
    property Status: string read FStatus write FStatus;

    class function Done(const Status: string): TMailActionResponse; static;
  end;

  // Parameters of the tools that act on one message.
  TMessageParams = class(TMicrosoftToolParams)
  private
    FMessageId: string;

  public
    [GraphId]
    [SchemaName('message_id')]
    [SchemaDescription('Id of the message, from mail_search or mail_list')]
    property MessageId: string read FMessageId write FMessageId;
  end;

  // The same for the tools that need a confirmation.
  TConfirmedMessageParams = class(TConfirmableToolParams)
  private
    FMessageId: string;

  public
    [GraphId]
    [SchemaName('message_id')]
    [SchemaDescription('Id of the message, from mail_search or mail_list')]
    property MessageId: string read FMessageId write FMessageId;
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Mail.Support;

{ TMessageListItem }

class function TMessageListItem.FromMessage(const Message: TMailMessage): TMessageListItem;
begin
  Result.Id             := Message.Id;
  Result.Subject        := Message.Subject;
  Result.Sender         := TMailSupport.FormatAddress(Message.From);
  Result.Received       := Message.ReceivedDateTime;
  Result.IsRead         := Message.IsRead;
  Result.HasAttachments := Message.HasAttachments;
  Result.Preview        := Message.BodyPreview;
end;

{ TMailListResponse }

class function TMailListResponse.FromResult(const SearchResult: TSearchMessagesResult): TMailListResponse;
begin
  Result := TMailListResponse.Create;

  var Items: TArray<TMessageListItem> := [];
  for var Message in SearchResult.Messages do
  begin
    Items := Items + [TMessageListItem.FromMessage(Message)];
  end;

  Result.Messages := Items;
  Result.HasMore := SearchResult.HasMore;
end;

{ TMailDraftResponse }

class function TMailDraftResponse.FromDraft(const Draft: TDraftResult): TMailDraftResponse;
begin
  Result := TMailDraftResponse.Create;
  Result.DraftId := Draft.Id;
  Result.Subject := Draft.Subject;
end;

{ TMailActionResponse }

class function TMailActionResponse.Done(const Status: string): TMailActionResponse;
begin
  Result := TMailActionResponse.Create;
  Result.Status := Status;
end;

end.
