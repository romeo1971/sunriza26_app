def build_workflow(image_path: str, audio_path: str, output_name: str = "sonic_result"):
    """
    Erzeugt ein funktionierendes Video-Workflow für ComfyUI.
    """

    workflow = {
        "prompt": {
            "1": {
                "class_type": "LoadImage",
                "inputs": {
                    "image": image_path
                }
            },
            "2": {
                "class_type": "LoadAudio",
                "inputs": {
                    "audio": audio_path
                }
            },
            "3": {
                "class_type": "SaveVideo",
                "inputs": {
                    "video": "1",
                    "audio": "2",
                    "filename_prefix": output_name,
                    "format": "video/mp4",
                    "codec": "libx264",
                    "fps": 25,
                    "save_metadata": True,
                    "save_output": True
                }
            }
        }
    }

    return workflow
