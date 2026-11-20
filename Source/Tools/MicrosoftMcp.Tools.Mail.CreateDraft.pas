unit MicrosoftMcp.Tools.Mail.CreateDraft;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailCreateDraftParams = class(TMicrosoftToolParams)
  private
    FToRecipients: TArray<string>;
    FCcRecipients: TArray<string>;
    FBccRecipients: TArray<string>;
    FSubject: string;
    FBody: string;
    FBodyType: string;

  public
    [Optional]
    [SchemaName('to')]
    [SchemaDescription('E-mail addresses of the recipients')]
    property ToRecipients: TArray<string> read FToRecipients write FToRecipients;

    [Optional]
    [SchemaName('cc')]
    property CcRecipients: TArray<string> read FCcRecipients write FCcRecipients;

    [Optional]
    [SchemaName('bcc')]
    property BccRecipients: TArray<string> read FBccRecipients write FBccRecipients;

    property Subject: string read FSubject write FSubject;

    [SchemaDescription('Body of the message; the signature of the mailbox is added')]
    property Body: string read FBody write FBody;

    [Optional]
    [SchemaName('body_type')]
    [SchemaEnum('text', 'html')]
    [SchemaDescription('text (default) or html')]
    property BodyType: string read FBodyType write FBodyType;
  end;

  TMailCreateDraftTool = class(TMicrosoftTool<TMailCreateDraftParams, TMailDraftResponse>)
  protected
    function Run(const Params: TMailCreateDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse; override;

  public
    const ToolName = 'mail_create_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Creates a draft in the Drafts folder of a mailbox. Nothing is sent; use mail_send_draft for that.';

{ TMailCreateDraftTool }

constructor TMailCreateDraftTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailCreateDraftTool.Run(const Params: TMailCreateDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse;
begin
  const IsHtml = SameText(Params.BodyType, TMailSupport.HtmlBodyType);

  const Draft = TMailSupport.Client(Graph).CreateDraft(Params.Subject, Params.Body,
                                                       TMailSupport.CleanRecipients(Params.ToRecipients),
                                                       TMailSupport.CleanRecipients(Params.CcRecipients),
                                                       TMailSupport.CleanRecipients(Params.BccRecipients),
                                                       IsHtml);

  Result := TMailDraftResponse.FromDraft(Draft);
end;

end.
