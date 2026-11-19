unit MicrosoftMcp.Mailbox.Slug;

interface

type
  // The short name of a mailbox: lowercase letters, digits and '-', 1 to 32 characters, starting with a letter or digit.
  TMailboxSlug = class
  private
    class function IsAsciiLetterOrDigit(const Letter: Char): Boolean; static;
    class function IsCombiningMark(const Letter: Char): Boolean; static;
    class function TryFold(const Letter: Char; out Folded: string): Boolean; static;
    class function FoldToSlugCharacters(const Text: string): string; static;
    class function LocalPartOf(const Text: string): string; static;
    class function CollapseDashes(const Text: string): string; static;

  public
    const MaxLength = 32;

    class function IsValid(const Value: string): Boolean; static;

    // Lowercase, diacritics removed, other characters become '-', at most MaxLength characters. For an address only the part before '@' counts.
    class function Suggest(const DisplayNameOrAddress: string): string; static;
  end;

implementation

uses
  System.SysUtils;

type
  TFoldRule = record
    Letters: string;
    Replacement: string;
  end;

const
  Dash = '-';
  FallbackSlug = 'mailbox';
  AddressSeparator = '@';
  FirstCombiningMark = #$0300;
  LastCombiningMark = #$036F;

  // Latin-1 and Latin Extended-A, written out here instead of asking the operating system to normalise: the result is
  // then the same on Windows and Linux.
  FoldRules: array[0..24] of TFoldRule = (
    (Letters: 'àáâãäåāăąÀÁÂÃÄÅĀĂĄ'; Replacement: 'a'),
    (Letters: 'æÆ'; Replacement: 'ae'),
    (Letters: 'çćĉċčÇĆĈĊČ'; Replacement: 'c'),
    (Letters: 'ďđðĎĐÐ'; Replacement: 'd'),
    (Letters: 'èéêëēĕėęěÈÉÊËĒĔĖĘĚ'; Replacement: 'e'),
    (Letters: 'ĝğġģĜĞĠĢ'; Replacement: 'g'),
    (Letters: 'ĥħĤĦ'; Replacement: 'h'),
    (Letters: 'ìíîïĩīĭįıÌÍÎÏĨĪĬĮİ'; Replacement: 'i'),
    (Letters: 'ĳĲ'; Replacement: 'ij'),
    (Letters: 'ĵĴ'; Replacement: 'j'),
    (Letters: 'ķĶ'; Replacement: 'k'),
    (Letters: 'ĺļľŀłĹĻĽĿŁ'; Replacement: 'l'),
    (Letters: 'ñńņňŉÑŃŅŇ'; Replacement: 'n'),
    (Letters: 'òóôõöøōŏőÒÓÔÕÖØŌŎŐ'; Replacement: 'o'),
    (Letters: 'œŒ'; Replacement: 'oe'),
    (Letters: 'ŕŗřŔŖŘ'; Replacement: 'r'),
    (Letters: 'śŝşšŚŜŞŠ'; Replacement: 's'),
    (Letters: 'ß'; Replacement: 'ss'),
    (Letters: 'ţťŧŢŤŦ'; Replacement: 't'),
    (Letters: 'ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ'; Replacement: 'u'),
    (Letters: 'ŵŴ'; Replacement: 'w'),
    (Letters: 'ýÿŷÝŸŶ'; Replacement: 'y'),
    (Letters: 'źżžŹŻŽ'; Replacement: 'z'),
    (Letters: 'þÞ'; Replacement: 'th'),
    (Letters: 'ŋŊ'; Replacement: 'ng')
  );

{ TMailboxSlug }

class function TMailboxSlug.IsValid(const Value: string): Boolean;
begin
  const HasValidLength = ((Value.Length >= 1) and (Value.Length <= MaxLength));
  if not HasValidLength then
  begin
    Exit(False);
  end;

  const StartsWithDash = (Value[1] = Dash);
  if StartsWithDash then
  begin
    Exit(False);
  end;

  for var Letter in Value do
  begin
    const IsAllowed = (IsAsciiLetterOrDigit(Letter) and not CharInSet(Letter, ['A'..'Z']));
    const IsDash = (Letter = Dash);
    if not (IsAllowed or IsDash) then
    begin
      Exit(False);
    end;
  end;

  Result := True;
end;

class function TMailboxSlug.Suggest(const DisplayNameOrAddress: string): string;
begin
  const Text = LocalPartOf(DisplayNameOrAddress.Trim);
  const Folded = CollapseDashes(FoldToSlugCharacters(Text));

  Result := Folded.Substring(0, MaxLength).TrimRight([Dash]);

  const IsEmpty = Result.IsEmpty;
  if IsEmpty then
  begin
    Result := FallbackSlug;
  end;
end;

class function TMailboxSlug.LocalPartOf(const Text: string): string;
begin
  const SeparatorPosition = Text.IndexOf(AddressSeparator);
  const HasLocalPart = (SeparatorPosition > 0);
  if HasLocalPart then
  begin
    Result := Text.Substring(0, SeparatorPosition);
  end
  else
  begin
    Result := Text;
  end;
end;

class function TMailboxSlug.FoldToSlugCharacters(const Text: string): string;
begin
  var Folded := '';

  for var Letter in Text do
  begin
    var Replacement: string;
    if CharInSet(Letter, ['A'..'Z']) then
    begin
      Folded := Folded + Chr(Ord(Letter) + (Ord('a') - Ord('A')));
    end
    else if IsAsciiLetterOrDigit(Letter) then
    begin
      Folded := Folded + Letter;
    end
    else if IsCombiningMark(Letter) then
    begin
      Continue;
    end
    else if TryFold(Letter, Replacement) then
    begin
      Folded := Folded + Replacement;
    end
    else
    begin
      Folded := Folded + Dash;
    end;
  end;

  Result := Folded;
end;

class function TMailboxSlug.CollapseDashes(const Text: string): string;
begin
  var Collapsed := '';

  for var Letter in Text do
  begin
    const RepeatsDash = ((Letter = Dash) and (Collapsed.IsEmpty or (Collapsed[Collapsed.Length] = Dash)));
    if not RepeatsDash then
    begin
      Collapsed := Collapsed + Letter;
    end;
  end;

  Result := Collapsed.TrimRight([Dash]);
end;

class function TMailboxSlug.TryFold(const Letter: Char; out Folded: string): Boolean;
begin
  Folded := '';

  for var Rule in FoldRules do
  begin
    const IsInRule = (Rule.Letters.IndexOf(Letter) >= 0);
    if IsInRule then
    begin
      Folded := Rule.Replacement;
      Exit(True);
    end;
  end;

  Result := False;
end;

class function TMailboxSlug.IsAsciiLetterOrDigit(const Letter: Char): Boolean;
begin
  Result := CharInSet(Letter, ['a'..'z', 'A'..'Z', '0'..'9']);
end;

class function TMailboxSlug.IsCombiningMark(const Letter: Char): Boolean;
begin
  Result := ((Letter >= FirstCombiningMark) and (Letter <= LastCombiningMark));
end;

end.
