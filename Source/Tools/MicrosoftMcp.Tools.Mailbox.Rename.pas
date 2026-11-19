unit MicrosoftMcp.Tools.Mailbox.Rename;

interface

uses
  MCPServer.Types,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Mailbox.Add,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailboxRenameParams = class(TMicrosoftToolParams)
  private
    FNewSlug: string;
    FDisplayName: string;

  public
    [Optional]
    [SchemaName('new_slug')]
    [SchemaDescription('New short name: lowercase letters, digits and "-", at most 32 characters; leave empty to keep it')]
    property NewSlug: string read FNewSlug write FNewSlug;

    [Optional]
    [SchemaName('display_name')]
    [SchemaDescription('New display name; leave empty to keep it')]
    property DisplayName: string read FDisplayName write FDisplayName;
  end;

  // A user tool: renaming must also work for a mailbox whose account is no longer linked.
  TMailboxRenameTool = class(TMicrosoftUserTool<TMailboxRenameParams, TMailboxChangeResponse>)
  protected
    function Run(const Params: TMailboxRenameParams; const UserId: string): TMailboxChangeResponse; override;

  public
    const ToolName = 'mailbox_rename';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  MicrosoftMcp.Mailbox.Service.Interfaces,
  MicrosoftMcp.Tools.Mailbox.Types;

resourcestring
  ToolDescription = 'Gives a mailbox another short name, another display name, or both.';

{ TMailboxRenameTool }

constructor TMailboxRenameTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(False, False);
end;

function TMailboxRenameTool.Run(const Params: TMailboxRenameParams; const UserId: string): TMailboxChangeResponse;
begin
  const Renamed = FServices.Mailboxes.Rename(UserId, Params.Mailbox, Params.NewSlug, Params.DisplayName);

  var Row := Default(TMailboxRow);
  for var Candidate in FServices.Mailboxes.List(UserId) do
  begin
    if Candidate.Mailbox.Slug = Renamed.Slug then
      Row := Candidate;
  end;

  Result := TMailboxChangeResponse.Create;
  Result.Mailbox := TMailboxItem.FromRow(Row);
end;

end.
