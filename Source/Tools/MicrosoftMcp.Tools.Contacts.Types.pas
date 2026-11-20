unit MicrosoftMcp.Tools.Contacts.Types;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.Contacts.Types,
  MicrosoftMcp.Tools.Base;

type
  // A contact as a list shows it.
  TContactSummary = record
    Id: string;

    [SchemaName('display_name')]
    DisplayName: string;

    [SchemaName('given_name')]
    GivenName: string;

    Surname: string;
    Email: string;
    Phone: string;
    Company: string;

    [SchemaName('job_title')]
    JobTitle: string;

    class function FromContact(const Contact: TContact): TContactSummary; static;
  end;

  TContactsSearchResponse = class
  private
    FContacts: TArray<TContactSummary>;

  public
    property Contacts: TArray<TContactSummary> read FContacts write FContacts;

    class function From(const Contacts: TArray<TContact>): TContactsSearchResponse; static;
  end;

  TContactDetailResponse = class
  private
    FId: string;
    FDisplayName: string;
    FGivenName: string;
    FSurname: string;
    FEmail: string;
    FBusinessPhone: string;
    FMobilePhone: string;
    FHomePhone: string;
    FCompany: string;
    FJobTitle: string;
    FDepartment: string;
    FOfficeLocation: string;
    FBusinessAddress: string;
    FHomeAddress: string;
    FBirthday: string;
    FPersonalNotes: string;

    class function FormatAddress(const Address: TPostalAddress): string; static;

  public
    property Id: string read FId write FId;

    [SchemaName('display_name')]
    property DisplayName: string read FDisplayName write FDisplayName;

    [SchemaName('given_name')]
    property GivenName: string read FGivenName write FGivenName;

    property Surname: string read FSurname write FSurname;
    property Email: string read FEmail write FEmail;

    [SchemaName('business_phone')]
    property BusinessPhone: string read FBusinessPhone write FBusinessPhone;

    [SchemaName('mobile_phone')]
    property MobilePhone: string read FMobilePhone write FMobilePhone;

    [SchemaName('home_phone')]
    property HomePhone: string read FHomePhone write FHomePhone;

    property Company: string read FCompany write FCompany;

    [SchemaName('job_title')]
    property JobTitle: string read FJobTitle write FJobTitle;

    property Department: string read FDepartment write FDepartment;

    [SchemaName('office_location')]
    property OfficeLocation: string read FOfficeLocation write FOfficeLocation;

    [SchemaName('business_address')]
    property BusinessAddress: string read FBusinessAddress write FBusinessAddress;

    [SchemaName('home_address')]
    property HomeAddress: string read FHomeAddress write FHomeAddress;

    property Birthday: string read FBirthday write FBirthday;

    [SchemaName('personal_notes')]
    property PersonalNotes: string read FPersonalNotes write FPersonalNotes;

    class function From(const Contact: TContact): TContactDetailResponse; static;
  end;

  TContactActionResponse = class
  private
    FStatus: string;
    FContactId: string;
    FDisplayName: string;

  public
    property Status: string read FStatus write FStatus;

    [SchemaName('contact_id')]
    property ContactId: string read FContactId write FContactId;

    [SchemaName('display_name')]
    property DisplayName: string read FDisplayName write FDisplayName;

    class function Done(const Status, ContactId, DisplayName: string): TContactActionResponse; static;
  end;

  TContactIdParams = class(TMicrosoftToolParams)
  private
    FContactId: string;

  public
    [SchemaName('contact_id')]
    [SchemaDescription('Id of the contact, from contacts_search')]
    property ContactId: string read FContactId write FContactId;
  end;

  TConfirmedContactIdParams = class(TConfirmableToolParams)
  private
    FContactId: string;

  public
    [SchemaName('contact_id')]
    [SchemaDescription('Id of the contact, from contacts_search')]
    property ContactId: string read FContactId write FContactId;
  end;

  // The fields of a contact that create and update can set.
  TContactFieldsParams = class(TMicrosoftToolParams)
  private
    FGivenName: string;
    FSurname: string;
    FEmail: string;
    FPhone: string;
    FCompany: string;
    FJobTitle: string;

  public
    [Optional]
    [SchemaName('given_name')]
    property GivenName: string read FGivenName write FGivenName;

    [Optional]
    property Surname: string read FSurname write FSurname;

    [Optional]
    property Email: string read FEmail write FEmail;

    [Optional]
    [SchemaDescription('Business phone number')]
    property Phone: string read FPhone write FPhone;

    [Optional]
    [SchemaDescription('Company name')]
    property Company: string read FCompany write FCompany;

    [Optional]
    [SchemaName('job_title')]
    property JobTitle: string read FJobTitle write FJobTitle;
  end;

implementation

uses
  System.SysUtils;

const
  CityLineFormat = '%s %s';

{ TContactSummary }

class function TContactSummary.FromContact(const Contact: TContact): TContactSummary;
begin
  Result.Id          := Contact.Id;
  Result.DisplayName := Contact.DisplayName;
  Result.GivenName   := Contact.GivenName;
  Result.Surname     := Contact.Surname;
  Result.Email       := Contact.Email;
  Result.Phone       := Contact.BusinessPhone;
  Result.Company     := Contact.Company;
  Result.JobTitle    := Contact.JobTitle;
end;

{ TContactsSearchResponse }

class function TContactsSearchResponse.From(const Contacts: TArray<TContact>): TContactsSearchResponse;
begin
  Result := TContactsSearchResponse.Create;

  var Items: TArray<TContactSummary> := [];
  for var Contact in Contacts do
  begin
    Items := Items + [TContactSummary.FromContact(Contact)];
  end;

  Result.Contacts := Items;
end;

{ TContactDetailResponse }

class function TContactDetailResponse.From(const Contact: TContact): TContactDetailResponse;
begin
  Result := TContactDetailResponse.Create;

  Result.Id             := Contact.Id;
  Result.DisplayName    := Contact.DisplayName;
  Result.GivenName      := Contact.GivenName;
  Result.Surname        := Contact.Surname;
  Result.Email          := Contact.Email;
  Result.BusinessPhone  := Contact.BusinessPhone;
  Result.MobilePhone    := Contact.MobilePhone;
  Result.HomePhone      := Contact.HomePhone;
  Result.Company        := Contact.Company;
  Result.JobTitle       := Contact.JobTitle;
  Result.Department     := Contact.Department;
  Result.OfficeLocation := Contact.OfficeLocation;
  Result.Birthday       := Contact.Birthday;
  Result.PersonalNotes  := Contact.PersonalNotes;

  Result.BusinessAddress := FormatAddress(Contact.BusinessAddress);
  Result.HomeAddress     := FormatAddress(Contact.HomeAddress);
end;

class function TContactDetailResponse.FormatAddress(const Address: TPostalAddress): string;
begin
  const CityLine = Format(CityLineFormat, [Address.PostalCode, Address.City]).Trim;
  const Parts: TArray<string> = [Address.Street, CityLine, Address.State, Address.Country];

  var Filled: TArray<string> := [];
  for var Part in Parts do
  begin
    if not Part.IsEmpty then
      Filled := Filled + [Part];
  end;

  Result := string.Join(', ', Filled);
end;

{ TContactActionResponse }

class function TContactActionResponse.Done(const Status, ContactId, DisplayName: string): TContactActionResponse;
begin
  Result := TContactActionResponse.Create;

  Result.Status      := Status;
  Result.ContactId   := ContactId;
  Result.DisplayName := DisplayName;
end;

end.
