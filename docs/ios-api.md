# iOS API Foundation

Native clients should authenticate with email/password, store the returned token in Keychain, and send it on every API request:

```http
Authorization: Bearer <token>
```

The web app still uses the same session as an HTTP-only cookie. The bearer token is the raw session token returned only at login/register time.

## Auth

`POST /api/auth/register`

```json
{ "email": "you@example.com", "password": "minimum-8-chars", "name": "Optional" }
```

`POST /api/auth/login`

```json
{ "email": "you@example.com", "password": "minimum-8-chars" }
```

Both return:

```json
{
  "user": { "id": "...", "email": "you@example.com", "name": null },
  "token": "..."
}
```

## Core Endpoints

`GET /api/articles?archived=false&search=&labelId=`

`POST /api/articles`

```json
{ "url": "https://example.com/article" }
```

`GET /api/articles/:id`

`PATCH /api/articles/:id`

```json
{ "archived": true }
```

`DELETE /api/articles/:id`

`GET /api/labels`

The Swift package at `ios/ReaderAPI` wraps these endpoints with typed async methods.
