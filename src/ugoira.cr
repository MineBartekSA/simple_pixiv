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
      filename = self.zip_basename if filename == ""
      res = HTTP::Client.get(self.zip_url, headers: HTTP::Headers{"Referer" => "https://app-api.pixiv.net/"})
      raise "non-200 response (#{res.status_code})" unless res.success?
      File.write filename, res.body
    end

    def video(ffmpeg_args : String = "-c:v libvpx-vp9 -crf 31 -pix_fmt yuv420p -f webm") : DownloadData
      final = IO::Memory.new

      temp_dir = "#{Dir.tempdir}/#{Random::Secure.hex}"

      HTTP::Client.get(self.zip_url, headers: HTTP::Headers{"Referer" => "https://app-api.pixiv.net/"}) do |res|
        raise "non-200 response (#{res.status_code})" unless res.success?

        Dir.mkdir_p temp_dir
        Log.debug { "Downloading ugiora to: #{temp_dir}" }

        Compress::Zip::Reader.open(res.body_io, true) do |zip|
          zip.each_entry do |entry|
            filepath = "#{temp_dir}/#{entry.filename}"
            File.write filepath, entry.io
          end
        end
      end

      concat = File.open "#{temp_dir}/concat.txt", "w"
      concat.puts "ffconcat version 1.0"
      self.frames.each do |frame|
        concat.puts "file #{frame.file}"
        concat.puts "duration #{frame.delay}ms"
      end
      concat.close

      Log.debug { "Finished writing ugiora and concat file" }

      args = [
        "-f", "concat",
        "-safe", "0",
        "-i", "#{temp_dir}/concat.txt",
        "-enc_time_base", "1/1000"
      ]
      args.concat ffmpeg_args.split(" ") if ffmpeg_args != ""
      args << "-"

      ffmpeg = Process.new("ffmpeg", args, input: :pipe, output: :pipe)

      spawn IO.copy ffmpeg.output, final

      # Wait for ffmpeg to finish
      status = ffmpeg.wait

      # Clean up
      Dir.new(temp_dir).each_child do |c|
        File.delete "#{temp_dir}/#{c}"
      end
      Dir.delete temp_dir

      # Check if ffmpeg succeded
      raise "ffmpeg failed" unless status.success?
      final.rewind

      name = self.basename
      proc = Process.new "file", ["--mime-type", "-"], input: :pipe, output: :pipe

      IO.copy final, proc.input, 512
      mime_io = IO::Memory.new
      spawn IO.copy proc.output, mime_io

      status = proc.wait
      raise "file failed to read mime-type" unless status.success?
      final.rewind
      mime = mime_io.to_s[12..-2]

      MIME.extensions(mime).first?.try { |ext| name += ext }

      DownloadData.new final, name, mime
    end

    def save_video(filename : String = "", ffmpeg_args : String = "")
      video = if ffmpeg_args == ""
        self.video
      else
        self.video ffmpeg_args
      end
      filename = video.filename if filename == ""
      File.write filename, video.data
    end

    def save_video_with_metadata(filename : String = "", ffmpeg_args : String = "")
      video = if ffmpeg_args == ""
        self.video
      else
        self.video ffmpeg_args
      end

      filename = video.filename if filename == ""

      # Pass the video through ffmpeg again to fix metadata
      metadata = Process.new("ffmpeg", ["-y", "-i", "-", "-c:v", "copy", "-c:a", "copy", "-f", "webm", filename], input: :pipe, output: :pipe)

      IO.copy video.data, metadata.input

      status = metadata.wait
      raise "ffmpeg matadata fix failed" unless status.success?
    end

    def zip_basename
      Path[self.zip_url.path].basename
    end

    def basename
      self.zip_basename[..-5]
    end
  end

  struct Frame
    include JSON::Serializable

    property file : String
    property delay : UInt16
  end
end
