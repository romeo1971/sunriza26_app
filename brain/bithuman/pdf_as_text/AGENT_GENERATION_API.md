# 🤖 Agent Generation API

**Early Access: bitHuman Agent Creation Service**

Programmatically create interactive avatar agents through our cloud-hosted REST API.

## 🔑 Authentication

Get your API secret from **imaginex.bithuman.ai**

## Base URL

```
https://public.api.bithuman.ai
```

## Endpoints

### Generate Agent

**POST /v1/agent/generate**

Create a new interactive avatar agent with customizable parameters.

#### Headers:
```
Content-Type: application/json
api-secret: YOUR_API_SECRET
```

#### Request Body:
```json
{
  "prompt": "string (optional)",
  "image": "string (optional)",
  "video": "string (optional)",
  "audio": "string (optional)"
}
```

#### Parameters:

| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `prompt` | string | Custom system prompt for the agent | `"You are a friendly AI assistant"` |
| `image` | string | URL or base64 data | `"https://example.com/image.jpg"` |
| `video` | string | URL or base64 data | `"https://example.com/video.mp4"` |
| `audio` | string | URL or base64 data | `"https://example.com/audio.mp3"` |

#### Response:
```json
{
  "success": true,
  "message": "Agent generation started",
  "agent_id": "A91XMB7113",
  "status": "processing"
}
```

#### Example Request:

```python
import requests

url = "https://public.api.bithuman.ai/v1/agent/generate"
headers = {
    "Content-Type": "application/json",
    "api-secret": "YOUR_API_SECRET"
}

payload = {
    "prompt": "You are a professional video content creator who helps with social media content."
}

response = requests.post(url, headers=headers, json=payload)
print(response.json())
```

#### Example with Media:

```python
payload = {
    "prompt": "You are an art critic who analyzes visual artworks.",
    "image": "https://example.com/artwork.jpg"
}

response = requests.post(url, headers=headers, json=payload)
```

---

### Get Agent Status

**GET /v1/agent/status/{agent_id}**

Retrieve the current status and details of a specific agent.

#### Headers:
```
api-secret: YOUR_API_SECRET
```

#### Path Parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `agent_id` | string | The unique identifier of the agent |

#### Response:
```json
{
  "success": true,
  "data": {
    "agent_id": "agent_id",
    "event_type": "lip_created",
    "status": "ready",
    "error_message": null,
    "created_at": "2025-08-01T13:58:51.907177+00:00",
    "updated_at": "2025-08-01T09:59:15.159901+00:00",
    "system_prompt": "your agent prompt",
    "image_url": "your_image_url",
    "video_url": "your_video_url",
    "name": "agent name",
    "model_url": "your model url"
  }
}
```

#### Status Values:
- **processing** - Agent is currently being generated
- **ready** - Agent generation completed successfully
- **failed** - Agent generation failed

#### Example Request:

```python
import requests

agent_id = "A81FMS8296"
url = f"https://public.api.bithuman.ai/v1/agent/status/{agent_id}"
headers = {
    "api-secret": "YOUR_API_SECRET"
}

response = requests.get(url, headers=headers)
print(response.json())
```

---

### Complete Example:

```python
import requests
import time

# Step 1: Create agent
generate_url = "https://public.api.bithuman.ai/v1/agent/generate"
headers = {
    "Content-Type": "application/json",
    "api-secret": "YOUR_API_SECRET"
}

payload = {
    "prompt": "You are a friendly AI assistant that helps with creative writing."
}

# Generate agent
response = requests.post(generate_url, headers=headers, json=payload)
result = response.json()
agent_id = result["agent_id"]
print(f"Agent created: {agent_id}")

# Step 2: Poll for completion
status_url = f"https://public.api.bithuman.ai/v1/agent/status/{agent_id}"
status_headers = {"api-secret": "YOUR_API_SECRET"}

while True:
    status_response = requests.get(status_url, headers=status_headers)
    status_data = status_response.json()
    status = status_data["data"]["status"]
    
    if status == "ready":
        print(f"Agent ready: {status_data['data']['model_url']}")
        break
    elif status == "failed":
        print("Generation failed")
        break
    
    time.sleep(5)  # Wait 5 seconds before checking again
```

---

## Error Handling

### Common HTTP Status Codes:

- **200** - Success
- **400** - Bad Request (invalid parameters)
- **401** - Unauthorized (invalid API secret)
- **429** - Rate Limit Exceeded
- **500** - Internal Server Error

### Error Response Format:

```json
{
  "error": "Invalid API secret",
  "code": "UNAUTHORIZED",
  "details": "Please check your API secret from imaginex.bithuman.ai"
}
```

---

## Flutter Integration

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<String?> createBitHumanAgent({
  String? imageUrl,
  String? audioUrl,
  String? prompt,
  required String apiSecret,
}) async {
  final response = await http.post(
    Uri.parse('https://public.api.bithuman.ai/v1/agent/generate'),
    headers: {
      'Content-Type': 'application/json',
      'api-secret': apiSecret,
    },
    body: json.encode({
      if (prompt != null) 'prompt': prompt,
      if (imageUrl != null) 'image': imageUrl,
      if (audioUrl != null) 'audio': audioUrl,
    }),
  );

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['agent_id'];
  }

  return null;
}
```

