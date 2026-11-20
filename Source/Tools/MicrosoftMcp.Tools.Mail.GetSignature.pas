unit MicrosoftMcp.Tools.Mail.GetSignature;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailSignatureResponse = class
  private
    FSignatureHtml: string;

  public
    [SchemaName('signature_html')]
    [SchemaDescription('The signature as HTML; empty when the mailbox has none')]
    property SignatureHtml: string read FSignatureHtml write FSignatureHtml;
  end;

  TMailGetSignatureTool = class(TMicrosoftTool<TMicrosoftToolParams, TMailSignatureResponse>)
  protected
    function Run(const Params: TMicrosoftToolParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailSignatureResponse; override;

  public
    const ToolName = 'mail_get_signature';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Returns the signature of a mailbox. mail_create_draft and mail_send add it to the message themselves.';

{ TMailGetSignatureTool }

constructor TMailGetSignatureTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkReadOnly(True);
end;

function TMailGetSignatureTool.Run(const Params: TMicrosoftToolParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailSignatureResponse;
begin
  Result := TMailSignatureResponse.Create;
  Result.SignatureHtml := TMailSupport.Client(Graph).GetMailboxSignature;
end;

end.
