# Local Backend Contract

This app can optionally send recipe links to your own Mac first before it falls back to public page fetching.

## App setting

Set the backend base URL in the in-app settings:

- Simulator example: `http://localhost:8080`
- Real iPhone example: `http://192.168.1.23:8080`

The app will call:

`POST {baseURL}/imports/link`

with a JSON body like:

```json
{
  "input": "🇺🇸保姆级教程 复刻全美超火的罗德岛水果塔！🍰 http://xhslink.com/o/912DZwOFNHp"
}
```

## Response shape

Your backend should return JSON. The app is tolerant about field naming, but this shape is the cleanest:

```json
{
  "source_url": "https://www.xiaohongshu.com/...",
  "resolved_url": "https://www.xiaohongshu.com/explore/...",
  "title": "罗德岛水果塔",
  "description": "",
  "body_text": "整理后的正文全文",
  "source_text": "可选，原始抓取文本",
  "images": [
    {
      "url": "https://...",
      "data_url": "data:image/jpeg;base64,..."
    }
  ],
  "image_urls": [
    "https://..."
  ]
}
```

## Notes

- `input` can be either a plain URL or the full "copy and open rednote" share text.
- The app can use either `images[].data_url` or `image_urls`.
- Returning inline image data is preferred for personal local use because the iPhone does not need to hotlink Xiaohongshu image URLs itself.
- If the backend request fails, the app falls back to direct public-page fetching.
