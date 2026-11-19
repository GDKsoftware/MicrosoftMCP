unit MicrosoftMcp.Tools.Mailbox.Remove;

interface

uses
  MCPServer.Types,
  MicrosoftMcp.Tools.Base,
  MicrosoftMcp.Tools.Services.Interfaces;

type
  TMailboxRemoveResponse = class
  private
    FRemoved: string;

  public
    [SchemaDescription('Short name of the removed mailbox')]
    property Removed: string read FRemoved write FRemoved;
  end;

  // A user tool: removing must also work for a mailbox whose account is no longer linked.
  TMailboxRemoveTool = class(TConfirmedMicrosoftUserTool<TConfirmableToolParams, TMailboxRemoveResponse>)
  protected
    function Summarize(const Params: TConfirmableToolParams; const UserId: string): string; override;
    function Run(const Params: TConfirmableToolParams; const UserId: string): TMailboxRemoveResponse; override;

  public
    const ToolName = 'mailbox_remove';

    constructor Create(const Services: IToolServices);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Mailbox.Types;

resourcestring
  ToolDescription = 'Removes a mailbox from this server. Its mail in Microsoft 365 stays untouched; only the short name disappears. ' +
                    'Needs confirmation: the first call returns a summary and a confirmation_token.';
  SummaryFormat = 'Remove mailbox "%s" (%s) from this server. The mail in Microsoft 365 is not touched; the mailbox can be added again with mailbox_add.';

{ TMailboxRemoveTool }

constructor TMailboxRemoveTool.Create(const Services: IToolServices);
begin
  inherited Create(Services);

  FName := ToolName;
  FDescription := ToolDescription;
  MarkChanging(True, True);
end;

function TMailboxRemoveTool.Summarize(const Params: TConfirmableToolParams; const UserId: string): string;
begin
  const Mailbox = FServices.Mailboxes.Get(UserId, Params.Mailbox);
  Result := Format(SummaryFormat, [Mailbox.Slug, Mailbox.DisplayName]);
end;

function TMailboxRemoveTool.Run(const Params: TConfirmableToolParams; const UserId: string): TMailboxRemoveResponse;
begin
  FServices.Mailboxes.Remove(UserId, Params.Mailbox);

  Result := TMailboxRemoveResponse.Create;
  Result.Removed := Params.Mailbox;
end;

end.
