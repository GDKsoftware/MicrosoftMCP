unit MicrosoftMcp.Mailbox.Types;

interface

{$SCOPEDENUMS ON}

type
  // Own is the mailbox of the linked account itself; Shared is a shared mailbox reached through that account.
  TMailboxKind = (Own, Shared);

  TMailboxKindHelper = record helper for TMailboxKind
    class function Parse(const Code: string): TMailboxKind; static;

    function Code: string;
  end;

  // A mailbox a user made available under a short name. Address is empty for an own mailbox.
  TMailbox = record
    UserId: string;
    Slug: string;
    DisplayName: string;
    Address: string;
    AccountKey: string;
    Kind: TMailboxKind;
    CreatedAtUtc: TDateTime;
  end;

implementation

uses
  System.SysUtils;

const
  OwnCode = 'own';
  SharedCode = 'shared';

{ TMailboxKindHelper }

class function TMailboxKindHelper.Parse(const Code: string): TMailboxKind;
begin
  if SameText(Code, OwnCode) then
  begin
    Result := TMailboxKind.Own;
  end
  else if SameText(Code, SharedCode) then
  begin
    Result := TMailboxKind.Shared;
  end
  else
  begin
    raise EConvertError.CreateFmt('Unknown mailbox kind "%s"', [Code]);
  end;
end;

function TMailboxKindHelper.Code: string;
begin
  case Self of
    TMailboxKind.Own    : Result := OwnCode;
    TMailboxKind.Shared : Result := SharedCode;
  else
    raise ENotSupportedException.CreateFmt('Unsupported mailbox kind: %d', [Ord(Self)]);
  end;
end;

end.
