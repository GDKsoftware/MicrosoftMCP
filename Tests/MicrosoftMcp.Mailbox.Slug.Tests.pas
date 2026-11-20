unit MicrosoftMcp.Mailbox.Slug.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMailboxSlugTests = class
  public
    [Test]
    [TestCase('Plain', 'gdk')]
    [TestCase('Digits', '2024')]
    [TestCase('DigitFirst', '1password')]
    [TestCase('WithDash', 'prive-kees')]
    [TestCase('SingleCharacter', 'a')]
    procedure ValidSlugs(const Value: string);

    [Test]
    procedure ValidSlugsIncludeTheMaximumLength;

    [Test]
    procedure InvalidSlugs;

    [Test]
    [TestCase('Space', 'my box')]
    [TestCase('Underscore', 'my_box')]
    [TestCase('At', 'a@b')]
    [TestCase('Dot', 'a.b')]
    procedure InvalidSlugsWithForbiddenCharacters(const Value: string);

    [Test]
    [TestCase('DisplayName', 'Privé Kees,prive-kees')]
    [TestCase('Address', 'projects@x.nl,projects')]
    [TestCase('Umlaut', 'Müller & Zoon,muller-zoon')]
    [TestCase('Sharp S', 'Straße,strasse')]
    [TestCase('Ligature', 'Æther Øre Å,aether-ore-a')]
    [TestCase('Uppercase accent', 'ÉCOLE,ecole')]
    [TestCase('Extended A', 'Łódź Čeština,lodz-cestina')]
    [TestCase('Dutch', 'Café Zoë,cafe-zoe')]
    [TestCase('Repeated separators', 'a   --  b,a-b')]
    [TestCase('Edges trimmed', '  !!GDK!!  ,gdk')]
    procedure SuggestStripsDiacriticsAndDomain(const Value, Expected: string);

    [Test]
    procedure SuggestStripsDiacriticsOfDecomposedLetters;

    [Test]
    procedure SuggestLimitsLengthWithoutTrailingDash;

    [Test]
    procedure SuggestFallsBackWhenNothingIsLeft;

    [Test]
    [TestCase('Mixed', 'Privé Kees')]
    [TestCase('Address', 'projects@x.nl')]
    [TestCase('Long', 'A very long display name that goes past the limit of thirty-two characters')]
    [TestCase('Symbols', '###')]
    [TestCase('Empty', '')]
    procedure SuggestAlwaysReturnsValidSlug(const Value: string);
  end;

implementation

uses
  System.SysUtils,
  MicrosoftMcp.Mailbox.Slug;

{ TMailboxSlugTests }

procedure TMailboxSlugTests.ValidSlugs(const Value: string);
begin
  Assert.IsTrue(TMailboxSlug.IsValid(Value));
end;

procedure TMailboxSlugTests.ValidSlugsIncludeTheMaximumLength;
begin
  const Value = StringOfChar('a', 32);

  Assert.IsTrue(TMailboxSlug.IsValid(Value));
end;

procedure TMailboxSlugTests.InvalidSlugs;
begin
  Assert.IsFalse(TMailboxSlug.IsValid(''), 'empty');
  Assert.IsFalse(TMailboxSlug.IsValid('-gdk'), 'starts with a dash');
  Assert.IsFalse(TMailboxSlug.IsValid('GDK'), 'uppercase');
  Assert.IsFalse(TMailboxSlug.IsValid('privé'), 'diacritic');
  Assert.IsFalse(TMailboxSlug.IsValid(StringOfChar('a', 33)), '33 characters');
end;

procedure TMailboxSlugTests.InvalidSlugsWithForbiddenCharacters(const Value: string);
begin
  Assert.IsFalse(TMailboxSlug.IsValid(Value));
end;

procedure TMailboxSlugTests.SuggestStripsDiacriticsAndDomain(const Value, Expected: string);
begin
  const Actual = TMailboxSlug.Suggest(Value);

  Assert.AreEqual(Expected, Actual);
end;

procedure TMailboxSlugTests.SuggestStripsDiacriticsOfDecomposedLetters;
begin
  const Decomposed = 'Prive' + #$0301 + ' Kees';

  const Actual = TMailboxSlug.Suggest(Decomposed);

  Assert.AreEqual('prive-kees', Actual);
end;

procedure TMailboxSlugTests.SuggestLimitsLengthWithoutTrailingDash;
begin
  const Value = StringOfChar('a', 31) + ' bbbbbb';

  const Actual = TMailboxSlug.Suggest(Value);

  Assert.AreEqual(StringOfChar('a', 31), Actual);
end;

procedure TMailboxSlugTests.SuggestFallsBackWhenNothingIsLeft;
begin
  const Actual = TMailboxSlug.Suggest('!!!');

  Assert.AreEqual('mailbox', Actual);
end;

procedure TMailboxSlugTests.SuggestAlwaysReturnsValidSlug(const Value: string);
begin
  const Actual = TMailboxSlug.Suggest(Value);

  Assert.IsTrue(TMailboxSlug.IsValid(Actual), Actual);
end;

end.
