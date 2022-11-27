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

    def save_zip(filename : String = "")
      filename = Path[self.zip_url.path].basename if filename == ""
      res = HTTP::Client.get(self.zip_url, headers: HTTP::Headers{"Referer" => "https://app-api.pixiv.net/"})
      raise "non-200 response (#{res.status_code})" unless res.success?
      File.write filename, res.body
    end

    def video(ffmpeg_args : String = "-c:v libvpx-vp9 -crf 32 -pix_fmt yuv420p -f webm") : IO::Memory
      final = IO::Memory.new

      res = HTTP::Client.get(self.zip_url, headers: HTTP::Headers{"Referer" => "https://app-api.pixiv.net/"})
      raise "non-200 response (#{res.status_code})" unless res.success?
      ugoira = res.body_io? || IO::Memory.new res.body

      args = [
        "-framerate", self.get_framerate.to_s, # TODO: Make frame delay adjust after transcoding
        "-i", "-"
      ]
      args.concat ffmpeg_args.split(" ") if ffmpeg_args != ""
      args << "-"

      ffmpeg = Process.new("ffmpeg", args, input: :pipe, output: :pipe)

      spawn IO.copy ffmpeg.output, final

      Compress::Zip::Reader.open(ugoira, true) do |zip|
        zip.each_entry do |entry|
          IO.copy entry.io, ffmpeg.input
        end
      end

      status = ffmpeg.wait
      raise "ffmpeg failed" unless status.success?
      final.rewind

      final
    end

    def save_video(filename : String = "", ffmpeg_args : String = "")
      filename = Path[self.zip_url.path].basename[..-5] + ".webm" if filename == ""
      video = if ffmpeg_args == ""
        self.video
      else
        self.video ffmpeg_args
      end
      File.write filename, video
    end

    private def get_framerate
      delays = self.frames.map &.delay
      delays.uniq!
      return 1000/delays[0] if delays.size == 1
      1000/delays.map_with_index(offset = 1) { |delay, i| delays[i - 1].gcd delay }[-1]
    end
  end

  struct Frame
    include JSON::Serializable

    property file : String
    property delay : UInt16
  end
end
