module Pixiv
  enum Restrict # TODO: Make a converter
    Public
    Private

    def to_s : String
      case self
      when Public
        "public"
      when Private
        "private"
      else
        raise "invalid Restrict enum value"
      end
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

  struct UserQuery
    include JSON::Serializable

    property user_previews : Array(UserPreview)
    @[JSON::Field(converter: Pixiv::URIConverter)]
    property next_url : URI?
  end

  struct UserPreview
    include JSON::Serializable

    property user : User
    property illusts : Array(Illustration)
    property novels : Array(JSON::Any) # TODO: Novel model
    property is_muted : Bool
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
end
