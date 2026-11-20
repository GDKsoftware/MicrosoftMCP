unit MicrosoftMcp.Tools.SharePoint.Types;

interface

uses
  MCPServer.Types,
  MSGraph.Graph.SharePoint.Types,
  MicrosoftMcp.Tools.Base;

type
  TSiteItem = record
    Id: string;
    Name: string;

    [SchemaName('display_name')]
    DisplayName: string;

    [SchemaName('web_url')]
    WebUrl: string;

    Description: string;

    class function FromSite(const Site: TSite): TSiteItem; static;
  end;

  TSitesResponse = class
  private
    FSites: TArray<TSiteItem>;
    FNote: string;

  public
    property Sites: TArray<TSiteItem> read FSites write FSites;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;

    class function From(const Sites: TArray<TSite>; const Note: string): TSitesResponse; static;
  end;

  TPageItem = record
    Id: string;
    Title: string;
    Name: string;

    [SchemaName('web_url')]
    WebUrl: string;

    [SchemaName('last_modified')]
    LastModified: string;

    class function FromPage(const Page: TSitePage): TPageItem; static;
  end;

  TPagesResponse = class
  private
    FPages: TArray<TPageItem>;
    FNote: string;

  public
    property Pages: TArray<TPageItem> read FPages write FPages;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;

    class function From(const Pages: TArray<TSitePage>; const Note: string): TPagesResponse; static;
  end;

  TPageContentResponse = class
  private
    FId: string;
    FTitle: string;
    FWebUrl: string;
    FContentHtml: string;
    FNote: string;

  public
    property Id: string read FId write FId;
    property Title: string read FTitle write FTitle;

    [SchemaName('web_url')]
    property WebUrl: string read FWebUrl write FWebUrl;

    [SchemaName('content_html')]
    [SchemaDescription('The text web parts of the page as HTML')]
    property ContentHtml: string read FContentHtml write FContentHtml;

    [SchemaDescription('Remark when the account behind a shared mailbox was used; empty otherwise')]
    property Note: string read FNote write FNote;

    class function From(const Page: TSitePage; const Note: string): TPageContentResponse; static;
  end;

  TSiteParams = class(TMicrosoftToolParams)
  private
    FSiteId: string;

  public
    [SchemaName('site_id')]
    [SchemaDescription('Id of the site, from sharepoint_search_sites')]
    property SiteId: string read FSiteId write FSiteId;
  end;

implementation

{ TSiteItem }

class function TSiteItem.FromSite(const Site: TSite): TSiteItem;
begin
  Result.Id          := Site.Id;
  Result.Name        := Site.Name;
  Result.DisplayName := Site.DisplayName;
  Result.WebUrl      := Site.WebUrl;
  Result.Description := Site.Description;
end;

{ TSitesResponse }

class function TSitesResponse.From(const Sites: TArray<TSite>; const Note: string): TSitesResponse;
begin
  Result := TSitesResponse.Create;

  var Items: TArray<TSiteItem> := [];
  for var Site in Sites do
  begin
    Items := Items + [TSiteItem.FromSite(Site)];
  end;

  Result.Sites := Items;
  Result.Note := Note;
end;

{ TPageItem }

class function TPageItem.FromPage(const Page: TSitePage): TPageItem;
begin
  Result.Id           := Page.Id;
  Result.Title        := Page.Title;
  Result.Name         := Page.Name;
  Result.WebUrl       := Page.WebUrl;
  Result.LastModified := Page.LastModifiedDateTime;
end;

{ TPagesResponse }

class function TPagesResponse.From(const Pages: TArray<TSitePage>; const Note: string): TPagesResponse;
begin
  Result := TPagesResponse.Create;

  var Items: TArray<TPageItem> := [];
  for var Page in Pages do
  begin
    Items := Items + [TPageItem.FromPage(Page)];
  end;

  Result.Pages := Items;
  Result.Note := Note;
end;

{ TPageContentResponse }

class function TPageContentResponse.From(const Page: TSitePage; const Note: string): TPageContentResponse;
begin
  Result := TPageContentResponse.Create;

  Result.Id          := Page.Id;
  Result.Title       := Page.Title;
  Result.WebUrl      := Page.WebUrl;
  Result.ContentHtml := Page.ContentHtml;
  Result.Note        := Note;
end;

end.
