# SimplePixiv

SimplePixiv is a simple wrapper around some of Pixiv API endpoints.

Currently, only authorization by already generated refresh_token is possible.

Inspired by:
- [PixivPy3](https://github.com/upbit/pixivpy)
- [get-pixivpy-token](https://github.com/eggplants/get-pixivpy-token) - You can get your refresh_token using this tool

## Usage

```crystal
require "simple_pixiv"

client = Pixiv::Client.new "<your refresh token>"

illustration = client.illust_detail 91822191
puts illustration.title_image
```

## Contributing

1. Fork it (<https://github.com/your-github-user/simple_pixiv/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Bartłomiej Skoczeń](https://github.com/your-github-user) - creator and maintainer
