# SOC TASK 1 - Kelompok 5

## Anggota Tim

| No | Nama | NRP | Task |
|----|------|-----|-------|
| 1 | Ahmad Yafi Ar Rizq | 5027241066 | Agent — Web Deployment & Testing|
| 2 | Gemilang Ananda Lingua | 5027241072 | Agent — Attack Simulation & Testing |
| 3 | Binar Najmuddin Mahya | 5027241101 | Manager — SIEM & SOAR Deployment|

---


## 📋 Deskripsi

Proyek ini mengimplementasikan sistem **Security Operations Center (SOC) otomatis** yang menggabungkan:

- **Wazuh** sebagai platform SIEM (Security Information and Event Management) untuk mendeteksi anomali traffic jaringan secara real-time
- **Shuffle** sebagai platform SOAR (Security Orchestration, Automation and Response) untuk mengotomatisasi respons terhadap ancaman yang terdeteksi

Ketika Wazuh mendeteksi traffic anomali (seperti serangan DDoS pada web server Nginx), alert dikirim secara otomatis ke Shuffle melalui webhook. Shuffle kemudian mengorkestrasi alur respons: mengekstrak IP penyerang, (opsional) memperkaya data dengan threat intelligence, lalu memblokir IP tersebut melalui Wazuh Active Response menggunakan `firewall-drop`.

### Tujuan Proyek

- Memahami konsep SIEM dan SOAR dalam lingkungan SOC
- Mengintegrasikan Wazuh dengan Shuffle secara end-to-end
- Mengotomatisasi pemblokiran IP berbahaya tanpa intervensi manual
- Mensimulasikan serangan DDoS dan memverifikasi respons otomatis

---

## 🏗️ Arsitektur

```
┌─────────────────────────────────────────────────────────────────┐
│                        AZURE VIRTUAL MACHINE                    │
│                                                                 │
│  ┌──────────────┐    webhook    ┌──────────────────────────────┐│
│  │              │ ────────────► │         SHUFFLE SOAR         ││
│  │    WAZUH     │               │                              ││
│  │    SIEM      │ ◄──────────── │  [Webhook] → [Extract IP]    ││
│  │              │  active resp  │       → [Wazuh API]          ││
│  └──────┬───────┘               └──────────────────────────────┘│
│         │ alert                                                 │
│         ▼                                                       │
│  ┌──────────────┐                                               │
│  │  Wazuh Agent │  ◄──── Traffic Anomali / DDoS                 │
│  │  (Nginx VM)  │                                               │
│  │              │                                               │
│  │  Nginx Web   │  http://20.6.95.104/                          │
│  │  Server      │                                               │
│  └──────────────┘                                               │
└─────────────────────────────────────────────────────────────────┘

         ▲
         │ Simulasi Serangan DDoS
         │
┌────────────────┐
│  Attacker VM   │
│  (hping3/      │
│   slowloris)   │
└────────────────┘
```

### Komponen Stack

| Komponen | Tools | Port |
|---|---|---|
| SIEM | Wazuh Manager + Dashboard | 443, 9200, 55000 |
| SOAR | Shuffle (Docker) | 3001 |
| Database SOAR | OpenSearch (Docker) | 9201 |
| Web Server Target | Nginx + Wazuh Agent | 80 |

---

## ⚙️ Instalasi

### Prasyarat

- 3x Azure VM Ubuntu 24.04 LTS
- Akses sudo/root di setiap VM
- Port yang dibuka di Azure NSG sesuai tabel berikut:

| VM | Peran | Port yang Dibuka |
|---|---|---|
| VM 1 | Wazuh Dashboard + Shuffle SOAR | `22`, `443`, `3001`, `55000` |
| VM 2 | Web Server (Nginx) + Wazuh Agent | `22`, `80` |
| VM 3 | Attacker | `22` |

---

## VM 1 — Wazuh Dashboard + Shuffle SOAR

> IP: `70.153.18.130`

### 1.1 Instalasi Wazuh (All-in-One)

Install Wazuh Manager, Indexer, dan Dashboard sekaligus:

```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh && sudo bash ./wazuh-install.sh -a
```

Final Output:

```
https://70.153.18.130
Username: admin
Password: <dari output instalasi>
```

---

### 1.2 Instalasi Shuffle SOAR (Docker)

**Pastikan Docker sudah berjalan:**

```bash
sudo systemctl start docker && sudo systemctl enable docker
sudo usermod -aG docker $USER
newgrp docker
```

**Clone dan konfigurasi Shuffle:**

```bash
git clone https://github.com/Shuffle/Shuffle
cd Shuffle
```

**edit `docker-compose.yml` karena port 9200 sudah dipakai Wazuh Indexer:**

```bash
nano docker-compose.yml
```

Ubah port OpenSearch dari `9200:9200` menjadi `9201:9200`:

```yaml
opensearch:
  ports:
    - 9201:9200   # ubah dari 9200:9200
```

**Fix permission dan kernel setting sebelum start:**

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo swapoff -a
sudo chown -R 1000:1000 shuffle-database
```

**Jalankan Shuffle:**

```bash
docker-compose up -d
```

**Verifikasi semua container berjalan:**

```bash
docker ps
```

Output yang diharapkan:

```
shuffle-frontend    Up
shuffle-backend     Up
shuffle-orborus     Up
shuffle-opensearch  Up
```

Akses Shuffle di: `http://70.153.18.130:3001`

---

### 1.3 Buat Workflow di Shuffle

1. Login ke Shuffle → **Automate → Workflows → + Create Workflow**
2. Beri nama: `Wazuh Block Anomaly Traffic`
3. Drag node **Webhook** dari panel Triggers ke workspace
4. Rename webhook menjadi `Wazuh_alerts`
5. Klik **Start** untuk mengaktifkan webhook
6. **Copy Webhook URI** (contoh: `https://70.153.18.130:3001/api/v1/hooks/webhook_xxxx`)

**Bangun chain workflow:**

```
[Webhook: Wazuh_alerts]
        ↓
[Tools: Regex — ekstrak $data.srcip]
        ↓
[HTTP POST: ambil Wazuh API token]
        ↓
[HTTP PUT: trigger firewall-drop via Wazuh API]
```

**Node HTTP — Ambil Token Wazuh:**
- Method: `POST`
- URL: `https://70.153.18.130:55000/security/user/authenticate`
- Header: `Authorization: Basic <base64(admin:password)>`

**Node HTTP — Blokir IP:**
- Method: `PUT`
- URL: `https://70.153.18.130:55000/active-response?agents_list=all`
- Body:
```json
{
  "command": "firewall-drop",
  "arguments": ["-", "null", "$srcip", "null"]
}
```

---

### 1.4 Konfigurasi Wazuh untuk Kirim Alert ke Shuffle

**Edit ossec.conf di Wazuh Manager:**

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Tambahkan di dalam blok `<ossec_config>`:

```xml
<!-- Integrasi dengan Shuffle SOAR -->
<integration>
  <name>shuffle</name>
  <hook_url>https://70.153.18.130:3001/api/v1/hooks/<WEBHOOK_ID></hook_url>
  <level>7</level>
  <alert_format>json</alert_format>
</integration>
```

**Tambahkan Active Response untuk memblokir IP:**

```xml
<active-response>
  <command>firewall-drop</command>
  <location>local</location>
  <rules_id>31151,31152</rules_id>
  <timeout>no</timeout>
</active-response>
```

**Restart Wazuh Manager:**

```bash
sudo systemctl restart wazuh-manager
```

---

## VM 2 — Web Deploy (Nginx + Wazuh Agent)

> IP: `20.6.95.104`

### 2.1 Instalasi Nginx

```bash
sudo apt update && sudo apt install nginx -y
sudo systemctl enable nginx && sudo systemctl start nginx
```

### 2.2 Deploy Halaman HTML

```bash
sudo nano /var/www/html/index.html
```

Isi dengan konten berikut:

```html
<!DOCTYPE html>
<html>
<head>
  <title>DDoS Lab</title>
</head>
<body>
  <h1>DDoS Lab Website</h1>
  <p>This page is used for Wazuh dashboard testing.</p>
</body>
</html>
```

Website dapat diakses di: **http://20.6.95.104/**

### 2.3 Instalasi Wazuh Agent

```bash
wget https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.5-1_amd64.deb \
  && sudo WAZUH_MANAGER='70.153.18.130' WAZUH_AGENT_NAME='yafi' dpkg -i ./wazuh-agent_4.14.5-1_amd64.deb
```

**Aktifkan dan jalankan agent:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```


---

## VM 3 — Attacker


### 3.1 Instalasi Tools Serangan

```bash
sudo apt update
sudo apt install hping3 nmap apache2-utils -y
pip3 install slowloris
```

### 3.2 Simulasi Serangan DDoS ke `http://20.6.95.104/`

**Metode 1 — hping3 (SYN Flood):**

```bash
sudo hping3 -S --flood -V -p 80 20.6.95.104
```

**Metode 2 — Slowloris (HTTP Slow Attack):**

```bash
slowloris 20.6.95.104 -p 80 -s 500
```

**Metode 3 — Apache Benchmark (HTTP Flood):**

```bash
ab -n 10000 -c 100 http://20.6.95.104/
```

**Metode 4 — Nmap Port Scan:**

```bash
sudo nmap -sS -A 20.6.95.104
```

---

## 🔥 Simulasi Serangan DDoS

Target: `http://20.6.95.104/` (Nginx Web Server)

### Metode 1 — hping3 (SYN Flood)

```bash
# Install hping3
sudo apt install hping3 -y

# Kirim SYN flood ke port 80
sudo hping3 -S --flood -V -p 80 20.6.95.104
```

### Metode 2 — Slowloris (HTTP Slow Attack)

```bash
# Install slowloris
pip3 install slowloris

# Jalankan serangan
slowloris 20.6.95.104 -p 80 -s 500
```

### Metode 3 — Apache Benchmark (HTTP Flood)

```bash
# Kirim 10000 request dengan 100 concurrent
ab -n 10000 -c 100 http://20.6.95.104/
```

### Metode 4 — Nmap Port Scan (Memicu Rules Wazuh)

```bash
sudo apt install nmap -y
sudo nmap -sS -A 20.6.95.104
```

---

## Verifikasi Respons Otomatis

**1. Cek alert di Wazuh Dashboard:**
- Buka `https://<IP_VM>` → **Security Events**
- Filter berdasarkan rule group: `web` atau `syscheck`
- Pastikan alert dengan level ≥ 7 muncul

**2. Cek workflow Shuffle terpicu:**
- Buka Shuffle → Workflow → klik **Executions**
- Setiap eksekusi menunjukkan langkah-langkah yang berhasil dijalankan

**3. Verifikasi IP terblokir di firewall:**

```bash
# Di mesin Wazuh Agent / Nginx server
sudo iptables -L INPUT -n | grep <IP_ATTACKER>

# Output yang diharapkan:
# DROP  tcp  -- <IP_ATTACKER>  0.0.0.0/0
```

**4. Test koneksi dari attacker (seharusnya gagal):**

```bash
curl -v http://20.6.95.104/
# Expected: connection timeout atau connection refused
```

---

## 🗂️ Struktur Direktori

```
~/Shuffle/
├── docker-compose.yml      # Konfigurasi Docker Shuffle
├── shuffle-database/       # Data persistent OpenSearch
└── .env                    # Environment variables

/var/ossec/etc/
├── ossec.conf              # Konfigurasi utama Wazuh
└── rules/
    └── local_rules.xml     # Custom rules (opsional)
```

---

## 🐛 Troubleshooting

| Masalah | Penyebab | Solusi |
|---|---|---|
| `Permission denied` saat `docker-compose up` | User tidak di grup docker | `sudo usermod -aG docker $USER && newgrp docker` |
| Port 9200 bentrok | Wazuh Indexer sudah pakai 9200 | Ubah ke `9201:9200` di docker-compose.yml |
| `vm.max_map_count too low` | Kernel limit terlalu rendah | `sudo sysctl -w vm.max_map_count=262144` |
| Shuffle backend tidak connect ke DB | OpenSearch crash | `sudo chown -R 1000:1000 shuffle-database && sudo swapoff -a` |
| SSH putus setelah docker-compose up | Docker mereset iptables | `sudo iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT` |
| Alert tidak masuk ke Shuffle | Webhook tidak aktif / URL salah | Pastikan webhook di-**Start** dan URL di ossec.conf benar |

---
