unit MicrosoftMcp.Tools.Mail.CreateForwardDraft;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailCreateForwardDraftParams = class(TMessageParams)
  private
    FToRecipients: TArray<string>;
    FBody: string;

  public
    [SchemaName('to')]
    [SchemaDescription('E-mail addresses to forward the message to')]
    property ToRecipients: TArray<string> read FToRecipients write FToRecipients;

    [Optional]
    [SchemaDescription('Text to put above the forwarded message')]
    property Body: string read FBody write FBody;
  end;

  TMailCreateForwardDraftTool = class(TMicrosoftTool<TMailCreateForwardDraftParams, TMailDraftResponse>)
  protected
    function Run(const Params: TMailCreateForwardDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse; override;

  public
    const ToolName = 'mail_create_forward_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Creates a draft that forwards a message. Nothing is sent; use mail_send_draft for that.';

{ TMailCreateForwardDraftTool }

constructor TMailCreateForwardDraftTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailCreateForwardDraftTool.Run(const Params: TMailCreateForwardDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse;
begin
  const Recipients = TMailSupport.RequireRecipients(Params.ToRecipients);

  const Draft = TMailSupport.Client(Graph).CreateForwardDraft(Params.MessageId, Params.Body, Recipients, nil, False);

  Result := TMailDraftResponse.FromDraft(Draft);
end;

end.
