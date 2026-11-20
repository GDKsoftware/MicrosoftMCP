unit MicrosoftMcp.Tools.Mailbox.Rename;

interface

uses
  MCPServer.Types,
  MicrosoftMcp.Mailbox.Types,
  MicrosoftMcp.Mailbox.Service.Interfaces,
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
  private
    function RowOf(const Renamed: TMailbox; const UserId: string): TMailboxRow;

  protected
    function Run(const Params: TMailboxRenameParams; const UserId: string): TMailboxChangeResponse; override;

  public
    const ToolName = 'mailbox_rename';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MCPServer.Logger,
  MicrosoftMcp.Tools.Mailbox.Types;

resourcestring
  ToolDescription = 'Gives a mailbox another short name, another display name, or both.';
  ListFailedFormat = 'Tool %s: the mailboxes could not be listed after the rename: %s';

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

  Result := TMailboxChangeResponse.Create;
  Result.Mailbox := TMailboxItem.FromRow(RowOf(Renamed, UserId));
end;

function TMailboxRenameTool.RowOf(const Renamed: TMailbox; const UserId: string): TMailboxRow;
begin
  Result := Default(TMailboxRow);
  Result.Mailbox := Renamed;
  Result.Status := TMailboxStatus.Unknown;

  // The rename is done; when the linked accounts cannot be read now, the answer still reports it, with status unknown.
  var Rows: TArray<TMailboxRow>;
  try
    Rows := FServices.Mailboxes.List(UserId);
  except
    on E: Exception do
    begin
      TLogger.Warning(ListFailedFormat, [ToolName, E.ClassName]);
      Exit;
    end;
  end;

  for var Candidate in Rows do
  begin
    if Candidate.Mailbox.Slug = Renamed.Slug then
      Result := Candidate;
  end;
end;

end.
