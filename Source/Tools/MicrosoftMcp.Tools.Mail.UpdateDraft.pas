unit MicrosoftMcp.Tools.Mail.UpdateDraft;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Http,
  MicrosoftMcp.Mailbox.Resolver.Interfaces,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mail.Types,
  MicrosoftMcp.Tools.Services.Interfaces,
  MicrosoftMcp.Tools.GraphId;

type
  TMailUpdateDraftParams = class(TMicrosoftToolParams)
  private
    FDraftId: string;
    FToRecipients: TArray<string>;
    FCcRecipients: TArray<string>;
    FBccRecipients: TArray<string>;
    FSubject: string;
    FBody: string;
    FBodyType: string;

  public
    [GraphId]
    [SchemaName('draft_id')]
    [SchemaDescription('Id of the draft, from mail_create_draft')]
    property DraftId: string read FDraftId write FDraftId;

    [Optional]
    [SchemaName('to')]
    [SchemaDescription('New recipients; leave out to keep the current ones')]
    property ToRecipients: TArray<string> read FToRecipients write FToRecipients;

    [Optional]
    [SchemaName('cc')]
    [SchemaDescription('New cc recipients; leave out to keep the current ones')]
    property CcRecipients: TArray<string> read FCcRecipients write FCcRecipients;

    [Optional]
    [SchemaName('bcc')]
    [SchemaDescription('New bcc recipients; leave out to keep the current ones')]
    property BccRecipients: TArray<string> read FBccRecipients write FBccRecipients;

    [Optional]
    [SchemaDescription('New subject; leave out to keep the current one')]
    property Subject: string read FSubject write FSubject;

    [Optional]
    [SchemaDescription('New body; leave out to keep the current one')]
    property Body: string read FBody write FBody;

    [Optional]
    [SchemaName('body_type')]
    [SchemaEnum('text', 'html')]
    [SchemaDescription('Format of the new body, text (default) or html')]
    property BodyType: string read FBodyType write FBodyType;
  end;

  TMailUpdateDraftTool = class(TMicrosoftTool<TMailUpdateDraftParams, TMailDraftResponse>)
  protected
    function Run(const Params: TMailUpdateDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse; override;

  public
    const ToolName = 'mail_update_draft';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MSGraph.Graph.Mail.Types,
  MicrosoftMcp.Tools.Mail.Support;

resourcestring
  ToolDescription = 'Changes a draft. Only the fields that are passed change; the others keep their value. Nothing is sent.';

{ TMailUpdateDraftTool }

constructor TMailUpdateDraftTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailUpdateDraftTool.Run(const Params: TMailUpdateDraftParams; const Mailbox: TResolvedMailbox; const Graph: TGraphHttpClient): TMailDraftResponse;
begin
  // Graph replaces the subject, body and to-recipients of a draft that are sent along, so the omitted ones are taken from the draft.
  const Mail = TMailSupport.Client(Graph);
  const Current = Mail.GetMessage(Params.DraftId, TMailBodyFormat.Html);

  const HasBody = (not Params.Body.IsEmpty);
  const IsHtml = ((not HasBody) or SameText(Params.BodyType, TMailSupport.HtmlBodyType));

  var Subject := Current.Subject;
  if not Params.Subject.IsEmpty then
    Subject := Params.Subject;

  var Body := Current.Body;
  if HasBody then
    Body := Params.Body;

  var ToRecipients := TMailSupport.AddressesOf(Current.ToRecipients);
  if Length(Params.ToRecipients) > 0 then
    ToRecipients := TMailSupport.CleanRecipients(Params.ToRecipients);

  const Draft = Mail.UpdateDraft(Params.DraftId, Subject, Body, ToRecipients,
                                 TMailSupport.CleanRecipients(Params.CcRecipients),
                                 TMailSupport.CleanRecipients(Params.BccRecipients),
                                 IsHtml);

  Result := TMailDraftResponse.FromDraft(Draft);
end;

end.
