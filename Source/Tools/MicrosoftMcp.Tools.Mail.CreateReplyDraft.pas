unit MicrosoftMcp.Tools.Mail.CreateReplyDraft;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailCreateReplyDraftParams = class(TMessageParams)
  private
    FBody: string;
    FReplyAll: Boolean;

  public
    [SchemaDescription('Text of the reply; the quoted original is added below it')]
    property Body: string read FBody write FBody;

    [Optional]
    [SchemaName('reply_all')]
    [SchemaDescription('Reply to everyone on the message instead of only the sender; default false')]
    property ReplyAll: Boolean read FReplyAll write FReplyAll;
  end;

  TMailCreateReplyDraftTool = class(TMicrosoftTool<TMailCreateReplyDraftParams, TMailDraftResponse>)
  protected
    function Run(const Params: TMailCreateReplyDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse; override;

  public
    const ToolName = 'mail_create_reply_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Creates a draft that replies to a message, to the sender or to everyone. Nothing is sent; use mail_send_draft for that.';

{ TMailCreateReplyDraftTool }

constructor TMailCreateReplyDraftTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailCreateReplyDraftTool.Run(const Params: TMailCreateReplyDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse;
begin
  const Draft = TMailSupport.Client(Graph).CreateReplyDraft(Params.MessageId, Params.Body, nil, False, Params.ReplyAll);

  Result := TMailDraftResponse.FromDraft(Draft);
end;

end.
