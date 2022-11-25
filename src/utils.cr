module Pixiv
  module RFC3339Converter
    def self.from_json(value : JSON::PullParser) : Time
      Time::Format::RFC_3339.parse value.read_string
    end

    def self.to_json(value : Time, json : JSON::Builder)
      json.string Time::Format::RFC_3339.format value
    end
  end

  module URIConverter
    def self.from_json(value : JSON::PullParser) : URI
      URI.parse value.read_string
    end

    def self.to_json(value : URI, json : JSON::Builder)
      json.string value.to_s
    end
  end
end
