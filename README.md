# สมชาย — Writing Instrument & Packaging Portfolio (Deploy-ready)

ดีพลอยได้ทันทีด้วย **Netlify** หรือ **GitHub Pages**

## โครงไฟล์
- `index.html` — ไฟล์เดียวจบ (มี Dark/Light, ฟิลเตอร์โปรเจกต์, Modal, หน้า Printcraft)
- `cv.pdf` — (ตัวอย่าง) วางทับด้วย CV จริงของคุณได้ทุกเมื่อ

## วิธี Deploy (ง่ายสุด)
### วิธีที่ 1: Netlify (Drag & Drop)
1) เข้า https://app.netlify.com/drop  
2) ลากไฟล์ `index.html` (หรือ ZIP ทั้งโฟลเดอร์) ไปปล่อย → ได้ URL ทันที  
3) ฟอร์มติดต่อใช้ได้เลย เพราะมี `data-netlify` ใส่ไว้แล้ว

> ถ้าจะอัปเดตไฟล์: กด “Deploys” → ลากเวอร์ชันใหม่ทับ

### วิธีที่ 2: GitHub Pages
1) สร้าง repository ใหม่ (Public)  
2) อัปโหลด `index.html` (และ `cv.pdf` ถ้ามี)  
3) ไปที่ **Settings → Pages → Deploy from a branch** เลือก `main`/`root`  
4) รอสักครู่ จะได้ URL `https://<user>.github.io/<repo>/`

## ปรับแก้คอนเทนต์
- เปิด `index.html` แล้วแก้ในส่วน:
  - อาร์เรย์ `PROJECTS = [...]` (ชื่อโปรเจกต์/ปี/แท็ก/ตัวเลขผลลัพธ์/ลิงก์)
  - ข้อมูลติดต่อในส่วน `#contact`
  - ปุ่มดาวน์โหลด `cv.pdf` (วางไฟล์จริงชื่อเดียวกันไว้ข้างๆ)

## เคล็ดลัด
- ต้องการโดเมนสวยๆ บน Netlify: Site settings → Domain management → Add domain
- อยากใส่ Analytics: แทรกสคริปต์ GA4 ก่อนปิด `</head>`
- ถ้าจะใส่ภาพจริง: เพิ่ม `<img>` ในการ์ดหรือใน modal ได้เลย (CDN หรือโฟลเดอร์ /images)

โชคดีในการลอนช์! 🚀
