module Pixiv
  struct Illustration
    include JSON::Serializable

    property id : UInt64
    property title : String
    property type : String
    property caption : String
    property tags : Array(Tag)
    property user : User
    property total_bookmarks : UInt64
    @[JSON::Field(converter: Pixiv::RFC3339Converter)]
    property create_date : Time

    property image_urls : ImageURLs

    property page_count : UInt8
    property meta_single_page : SingleMeta
    property meta_pages : Array(ImageBox)

    property sanity_level : UInt8
    property restrict : UInt8
    property x_restrict : UInt8

    def is_nsfw : Bool
      self.x_restrict != 0
    end

    # Get title image URL in desired quality
    def title_image(quality : ImageDetail = ImageDetail::Original) : String
      if quality == ImageDetail::Original
        url = self.meta_pages[0].get quality if (url = self.meta_single_page.url) == ""
        url
      else
        self.image_urls.get quality
      end
    end

    # Get page URL in desired quality
    def get(page : UInt8 = 1, quality : ImageDetail = ImageDetail::Original) : String
      raise "invalid page number" if page == 0 || page > self.page_count
      if self.page_count == 1
        self.title_image quality
      else
        self.meta_pages[page - 1].image_urls.get quality
      end
    end

    # Download illustration to memory
    def download(page : UInt8 = 1, quality : ImageDetail = ImageDetail::Original) : DownloadData
      url = URI.parse self.get page, quality
      res = HTTP::Client.get url, headers: HTTP::Headers{"Referer" => "https://app-api.pixiv.net/"}
      unless res.success?
        Log.error { "Download Status: #{res.status} (#{res.status_code})" }
        raise "download failed"
      end
      io = res.body_io? || IO::Memory.new res.body
      DownloadData.new io, Path[url.path].basename, res.headers["Content-Type"]
    end
  end

  enum ImageDetail
    Original
    Large
    Medium
    SquareMedium
  end

  struct ImageURLs
    include JSON::Serializable

    property square_medium : String
    property medium : String
    property large : String
    property original : String?

    def get(quality : ImageDetail = ImageDetail::Original) : String
      case quality
      when ImageDetail::Original
        self.original || self.large # Return the highest quality possible
      when ImageDetail::Large
        self.large
      when ImageDetail::Medium
        self.medium
      when ImageDetail::SquareMedium
        self.square_medium
      else
        raise "invalid quality"
      end
    end
  end

  struct ImageBox
    include JSON::Serializable

    property image_urls : ImageURLs

    def get(quality : ImageDetail = ImageDetail::Original) : String
      self.image_urls.get quality
    end
  end

  struct SingleMeta
    include JSON::Serializable

    property original_image_url : String = ""

    def url : String
      self.original_image_url
    end
  end

  struct User
    include JSON::Serializable

    property id : UInt64
    property name : String
    property account : String
    property profile_image_urls : Avatar
  end

  struct Tag
    include JSON::Serializable

    property name : String
    property translated_name : String?

    def get_name : String
      self.translated_name | self.name
    end
  end

  struct DownloadData
    property filename : String
    property type : String
    property data : IO

    def initialize(@data, @filename, @type)
    end

    def save(filename : String = "")
      filename = self.filename if filename == ""
      File.write filename, self.data
    end
  end

  enum Sort
    None
    DateDesc
    DateAsc
    PopularDesc
    PopularAsc # TODO: Test

    def to_s : String
      case self
      when DateDesc
        "date_desc"
      when DateAsc
        "date_asc"
      when PopularDesc
        "popular_desc"
      when PopularAsc
        "popular_asc"
      else
        ""
      end
    end
  end

  struct UserSearch
    include JSON::Serializable

    property user_previews : Array(UserPreview)
    property next_url : String?
  end

  struct UserPreview
    include JSON::Serializable

    property user : User
    property illusts : Array(Illustration)
    property novels : Array(JSON::Any) # TODO: Novel model
  end

  struct BookmarkPage
    include JSON::Serializable

    property illusts : Array(Illustration)
    @[JSON::Field(converter: Pixiv::URIConverter)]
    property next_url : URI

    def next_id : UInt64
      self.next_url.query_params["max_bookmark_id"].to_u64
    end
  end

  struct IllustrationSeries
    include JSON::Serializable

    property illust_series_detail : SeriesDetails
    property illust_series_first_illust : Illustration
    property illusts : Array(Illustration)
    property next_url : String? # TODO: Find out what exactly it contains
  end

  struct SeriesDetails
    include JSON::Serializable

    property id : UInt64
    property title : String
    property caption : String
    property cover_image_urls : Avatar
    property series_work_count : UInt16
    @[JSON::Field(converter: Pixiv::RFC3339Converter)]
    property create_date : Time
  end

  struct Avatar
    include JSON::Serializable

    property medium : String

    def url : String
      self.medium
    end
  end
end
