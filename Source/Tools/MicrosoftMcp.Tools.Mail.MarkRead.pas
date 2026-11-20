unit MicrosoftMcp.Tools.Mail.MarkRead;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailMarkReadParams = class(TMessageParams)
  private
    FIsRead: Boolean;

  public
    [SchemaName('is_read')]
    [SchemaDescription('true marks the message as read, false as unread')]
    property IsRead: Boolean read FIsRead write FIsRead;
  end;

  TMailMarkReadTool = class(TMicrosoftTool<TMailMarkReadParams, TMailActionResponse>)
  protected
    function Run(const Params: TMailMarkReadParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse; override;

  public
    const ToolName = 'mail_mark_read';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Mail.Support;

const
  ReadStatus = 'marked as read';
  UnreadStatus = 'marked as unread';

resourcestring
  ToolDescription = 'Marks a message as read or unread.';

{ TMailMarkReadTool }

constructor TMailMarkReadTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailMarkReadTool.Run(const Params: TMailMarkReadParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailActionResponse;
begin
  TMailSupport.Client(Graph).MarkMessageAsRead(Params.MessageId, Params.IsRead);

  if Params.IsRead then
    Result := TMailActionResponse.Done(ReadStatus)
  else
    Result := TMailActionResponse.Done(UnreadStatus);
end;

end.
