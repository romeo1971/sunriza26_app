#!/usr/bin/env python3
"""
Sunriza.com Web Scraper
Extrahiert alle Bilder, Videos, Texte und erstellt Flutter Assets
"""

import requests
from bs4 import BeautifulSoup
import os
import json
import re
from urllib.parse import urljoin, urlparse
import time

def scrape_sunriza():
    """Scrapt alle Inhalte von sunriza.com"""
    
    base_url = "https://sunriza.com"
    
    print("🚀 Scraping sunriza.com...")
    
    # Lade die Hauptseite
    response = requests.get(base_url)
    response.raise_for_status()
    
    soup = BeautifulSoup(response.content, 'html.parser')
    
    # Erstelle Ordner-Struktur
    os.makedirs("assets/scraped/images", exist_ok=True)
    os.makedirs("assets/scraped/data", exist_ok=True)
    
    scraped_data = {
        "title": "",
        "description": "",
        "images": [],
        "videos": [],
        "texts": [],
        "sections": []
    }
    
    # 1. Titel extrahieren
    title = soup.find('title')
    if title:
        scraped_data["title"] = title.get_text().strip()
    
    # 2. Meta Description
    meta_desc = soup.find('meta', attrs={'name': 'description'})
    if meta_desc:
        scraped_data["description"] = meta_desc.get('content', '')
    
    # 3. Alle Bilder finden und herunterladen
    print("📸 Extrahiere Bilder...")
    images = soup.find_all('img')
    
    for i, img in enumerate(images):
        src = img.get('src')
        if src:
            # Vollständige URL erstellen
            img_url = urljoin(base_url, src)
            
            # Dateiname generieren
            parsed_url = urlparse(img_url)
            filename = os.path.basename(parsed_url.path)
            if not filename or '.' not in filename:
                filename = f"image_{i+1}.jpg"
            
            try:
                # Bild herunterladen
                img_response = requests.get(img_url)
                img_response.raise_for_status()
                
                # Speichern
                img_path = f"assets/scraped/images/{filename}"
                with open(img_path, 'wb') as f:
                    f.write(img_response.content)
                
                scraped_data["images"].append({
                    "filename": filename,
                    "original_url": img_url,
                    "alt_text": img.get('alt', ''),
                    "local_path": img_path
                })
                
                print(f"✅ Bild gespeichert: {filename}")
                time.sleep(0.5)  # Rate limiting
                
            except Exception as e:
                print(f"❌ Fehler beim Laden von {img_url}: {e}")
    
    # 4. YouTube Videos finden
    print("🎥 Suche YouTube Videos...")
    
    # Suche nach iframe YouTube embeds
    youtube_iframes = soup.find_all('iframe', src=re.compile(r'youtube\.com/embed/'))
    for iframe in youtube_iframes:
        src = iframe.get('src')
        if src:
            # Video ID extrahieren
            match = re.search(r'youtube\.com/embed/([^?&]+)', src)
            if match:
                video_id = match.group(1)
                scraped_data["videos"].append({
                    "platform": "youtube",
                    "video_id": video_id,
                    "embed_url": src,
                    "title": iframe.get('title', '')
                })
                print(f"✅ YouTube Video gefunden: {video_id}")
    
    # Suche nach YouTube Links
    youtube_links = soup.find_all('a', href=re.compile(r'youtube\.com/watch\?v='))
    for link in youtube_links:
        href = link.get('href')
        if href:
            match = re.search(r'v=([^&]+)', href)
            if match:
                video_id = match.group(1)
                scraped_data["videos"].append({
                    "platform": "youtube",
                    "video_id": video_id,
                    "watch_url": href,
                    "title": link.get_text().strip()
                })
                print(f"✅ YouTube Link gefunden: {video_id}")
    
    # 5. Texte extrahieren
    print("📝 Extrahiere Texte...")
    
    # Hauptüberschriften
    for tag in ['h1', 'h2', 'h3']:
        headers = soup.find_all(tag)
        for header in headers:
            text = header.get_text().strip()
            if text:
                scraped_data["texts"].append({
                    "type": tag,
                    "content": text,
                    "class": header.get('class', [])
                })
    
    # Paragraphen
    paragraphs = soup.find_all('p')
    for p in paragraphs:
        text = p.get_text().strip()
        if text and len(text) > 20:  # Nur längere Texte
            scraped_data["texts"].append({
                "type": "p",
                "content": text,
                "class": p.get('class', [])
            })
    
    # 6. Spezielle Sektionen
    print("🔍 Analysiere Sektionen...")
    
    # Suche nach Angular/Ionic Komponenten
    sections = soup.find_all(['ion-content', 'ion-card', 'section', 'div'], class_=re.compile(r'section|content|card|hero'))
    for section in sections:
        section_text = section.get_text().strip()
        if section_text and len(section_text) > 50:
            scraped_data["sections"].append({
                "tag": section.name,
                "class": section.get('class', []),
                "content": section_text[:500] + "..." if len(section_text) > 500 else section_text
            })
    
    # 7. Daten speichern
    with open("assets/scraped/data/sunriza_content.json", 'w', encoding='utf-8') as f:
        json.dump(scraped_data, f, indent=2, ensure_ascii=False)
    
    print(f"""
🎉 Scraping abgeschlossen!
📊 Statistiken:
   - Bilder: {len(scraped_data['images'])}
   - Videos: {len(scraped_data['videos'])}
   - Texte: {len(scraped_data['texts'])}
   - Sektionen: {len(scraped_data['sections'])}

💾 Daten gespeichert in: assets/scraped/
    """)
    
    return scraped_data

if __name__ == "__main__":
    try:
        scrape_sunriza()
    except Exception as e:
        print(f"❌ Fehler: {e}")
