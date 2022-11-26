module Pixiv
  class Client
    # Get Illustration details
    def illust_detail(illust_id : UInt64) : Illustration
      res = self.get "/v1/illust/detail", illust_id: illust_id
      response_error res, "illust request failed" unless res.success?
      IllustBox.from_json(res.body).illust
    end

    # Get Illustration Series detials
    def illust_series(series_id : UInt64) : IllustrationSeries
      res = self.get "/v1/illust/series", illust_series_id: series_id
      response_error res, "illust series request failed" unless res.success?
      IllustrationSeries.from_json res.body
    end

    # Get related Illustrations
    def illust_related(illust_id : UInt64, offset : UInt64? = nil, seed : UInt64 | Array(UInt64) | Nil = nil, viewed : UInt64 | Array(UInt64) | Nil = nil) : RelatedIllustrations
      params = {} of String => UInt64
      offset.try { |o| params["offset"] = o }
      seed.try do |s|
        if s.is_a?(UInt64)
          params["seed_illust_ids[0]"] = s
        else
          s.each_with_index do |id, i|
            params["seed_illust_ids[#{i}]"] = id
          end
        end
      end
      viewed.try do |v|
        if v.is_a?(UInt64)
          params["viewed[0]"] = v
        else
          v.each_with_index do |id, i|
            params["viewed[#{i}]"] = id
          end
        end
      end
      res = self.get "/v2/illust/related", params, illust_id: illust_id
      response_error res, "illust related request failed" unless res.success?
      body = res.body
      Log.debug { JSON.parse(body).dig("next_url") }
      box = RelatedBox.from_json body
      RelatedIllustrations.new illust_id, box.illusts, box.next_data
    end

    def next_illust_related(related : RelatedIllustrations) : RelatedIllustrations
      self.illust_related related.related_to, seed: related.next_data.seed, viewed: related.next_data.viewed
    end

    # Internal structures

    private struct RelatedBox
      include JSON::Serializable

      property illusts : Array(Illustration)
      @[JSON::Field(converter: Pixiv::URIConverter)]
      property next_url : URI

      def next_data : NextData
        seed = [] of UInt64
        viewed = [] of UInt64
        self.next_url.query_params.each do |key, value|
          case key
          when .starts_with? "seed_illust_ids"
            seed << value.to_u64
          when .starts_with? "viewed"
            viewed << value.to_u64
          end
        end
        NextData.new seed, viewed
      end
    end

    private struct IllustBox
      include JSON::Serializable

      property illust : Illustration
    end
  end

  # Public structures

  struct Illustration
    include JSON::Serializable

    property id : UInt64
    property title : String
    property type : String
    property caption : String
    property tags : Array(Tag)
    property user : User
    property series : SeriesInfo?
    property total_view : UInt64
    property total_bookmarks : UInt64
    @[JSON::Field(converter: Pixiv::RFC3339Converter)]
    property create_date : Time

    property image_urls : ImageURLs

    property page_count : UInt8
    property meta_single_page : SingleMeta
    property meta_pages : Array(ImageBox)

    property sanity_level : UInt8
    property restrict : UInt8 # TODO: Use Restrict enum?
    property x_restrict : UInt8

    property is_bookmarked : Bool

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

  struct Tag
    include JSON::Serializable

    property name : String
    property translated_name : String?

    def get_name : String
      self.translated_name || self.name
    end
  end

  struct SeriesInfo
    include JSON::Serializable

    property id : UInt64
    property title : String
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

  struct SingleMeta
    include JSON::Serializable

    property original_image_url : String = ""

    def url : String
      self.original_image_url
    end
  end

  struct ImageBox
    include JSON::Serializable

    property image_urls : ImageURLs

    def get(quality : ImageDetail = ImageDetail::Original) : String
      self.image_urls.get quality
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

  struct RelatedIllustrations
    include JSON::Serializable

    property related_to : UInt64
    property illusts : Array(Illustration)
    @[JSON::Field(ignore: true)]
    property next_data : NextData

    def initialize(@related_to, @illusts, @next_data)
    end
  end

  struct NextData
    property seed : Array(UInt64)
    property viewed : Array(UInt64)

    def initialize(@seed, @viewed)
    end
  end
end
