module Pixiv
  class Client
    def ugoira_metadata(illust_id : UInt64) : Ugoira
      res = self.get "/v1/ugoira/metadata", illust_id: illust_id
      response_error res, "ugoira request failed" unless res.success?
      box = UgoiraBox.from_json(res.body).ugoira_metadata
      Ugoira.new URI.parse(box.zip_urls.url), box.frames
    end

    # Internal strucutres

    private struct UgoiraBox
      include JSON::Serializable

      property ugoira_metadata : MetaBox
    end

    struct MetaBox
      include JSON::Serializable

      property zip_urls : Avatar # Note: this isn't a "avatar", but this field uses the same strucutre as a avatar structure, so we are reusing this struct
      property frames : Array(Frame)
    end
  end

  # Public structures

  struct Ugoira
    include JSON::Serializable

    @[JSON::Field(converter: Pixiv::URIConverter)]
    property zip_url : URI
    property frames : Array(Frame)

    def initialize(@zip_url, @frames)
    end
  end

  struct Frame
    include JSON::Serializable

    property file : String
    property delay : UInt16
  end
end
