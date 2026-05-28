# SOC TASK 1 - Kelompok 5

## Anggota Tim

| No | Nama | NRP | Task |
|----|------|-----|-------|
| 1 | Ahmad Yafi Ar Rizq | 5027241066 | Agent — Web Deployment & Testing|
| 2 | Gemilang Ananda Lingua | 5027241072 | Agent — Attack Simulation & Testing |
| 3 | Binar Najmuddin Mahya | 5027241101 | Manager — SIEM & SOAR Deployment|

---

## Deskripsi

Proyek ini mengimplementasikan sistem **Security Operations Center (SOC) otomatis** yang menggabungkan:

- **Wazuh** sebagai platform SIEM (Security Information and Event Management) untuk mendeteksi anomali traffic jaringan secara real-time
- **Wazuh Active Response** sebagai engine pemblokiran IP otomatis berbasis rules (built-in, tanpa install tambahan)

Ketika Wazuh mendeteksi traffic anomali (seperti serangan DDoS pada web server Nginx), Active Response langsung memblokir IP penyerang via `firewall-drop`. Secara paralel, alert dikirim ke n8n melalui webhook untuk divisualisasikan sebagai workflow otomasi.

### Kenapa Kombinasi Ini?

| Opsi | Keterangan |
|---|---|
| Wazuh Active Response saja | ✅ Stabil, instant, tapi tidak ada UI visual |

### Tujuan Proyek

- Memahami konsep SIEM dan SOAR dalam lingkungan SOC
- Mengimplementasikan respons otomatis pemblokiran IP berbahaya
- Memvisualisasikan alur orkestrasi keamanan via n8n
- Mensimulasikan serangan DDoS dan memverifikasi respons otomatis

---

## Arsitektur

```
┌─────────────────────────┐        ┌──────────────────────────────────┐
│   VM 1                  │        │   VM 2                           │
│   70.153.18.130         │        │   20.6.95.104                    │
│                         │        │                                  │
│  ┌─────────────────┐    │ alert  │  ┌────────────┐  ┌────────────┐  │
│  │   Wazuh SIEM    │◄───┼────────┼──│Wazuh Agent │  │   Nginx    │  │
│  │   + Dashboard   │    │        │  └────────────┘  │ Web Server │  │
│  └────────┬────────┘    │        │                  └────────────┘  │
│           │             │        └──────────────────────┬───────────┘
│    ┌──────┴──────┐      │                               │
│    │             │      │  firewall-drop                │ HTTP traffic
│    │  Active     │──────┼───────────────────────────────┘
│    │  Response   │      │
│    └──────┬──────┘      │
│           │ webhook     │        ┌──────────────────────────────────┐
│           ▼             │        │   VM 3 - Attacker                │
│  ┌─────────────────┐    │        │                                  │
│  │   n8n SOAR      │    │        │  hping3 / slowloris / ab / nmap  │
│  │   :5678         │    │        │  ──────────────────────────────► │
│  └─────────────────┘    │        │          20.6.95.104:80          │
└─────────────────────────┘        └──────────────────────────────────┘
```

### Komponen Stack

| Komponen | Tools | Port |
|---|---|---|
| SIEM | Wazuh Manager + Dashboard | 443, 9200, 55000 |
| Auto Block | Wazuh Active Response (firewall-drop) | built-in |
| Web Server Target | Nginx + Wazuh Agent | 80 |

---

## Instalasi

### Prasyarat

- 3x Azure VM Ubuntu 22.04 LTS
- Akses sudo/root di setiap VM
- Port yang dibuka di Azure NSG:

| VM | Peran | Port yang Dibuka |
|---|---|---|
| VM 1 | Wazuh Dashboard + n8n SOAR | `22`, `443`, `5678`, `55000` |
| VM 2 | Web Server (Nginx) + Wazuh Agent | `22`, `80` |
| VM 3 | Attacker | `22` |

---

## VM 1 — Wazuh Dashboard + n8n SOAR

> IP: `70.153.18.130`

### 1.1 Instalasi Wazuh (All-in-One)

Install Wazuh Manager, Indexer, dan Dashboard sekaligus:

```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh && sudo bash ./wazuh-install.sh -a
```

Simpan password yang muncul di akhir instalasi. Akses dashboard di:

```
https://70.153.18.130
Username: admin
Password: <dari output instalasi>
```

---

### 1.2 Konfigurasi Wazuh Active Response

Active Response adalah fitur built-in Wazuh untuk memblokir IP otomatis tanpa tools tambahan.

```bash
sudo nano /var/ossec/etc/ossec.conf
```

Tambahkan sebelum `</ossec_config>`:

```xml
<!-- Active Response: blokir IP otomatis saat terdeteksi anomali -->
<active-response>
  <command>firewall-drop</command>
  <location>local</location>
  <level>7</level>
  <timeout>600</timeout>
</active-response>
```

Restart Wazuh Manager:

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

**Verifikasi agent terdaftar** (dari VM 1):

```bash
sudo /var/ossec/bin/agent_control -l
```

---

## VM 3 — Attacker

> VM terpisah, bukan bagian dari infrastruktur monitoring

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

## Verifikasi Respons Otomatis

### 1. Cek Alert di Wazuh Dashboard

- Buka `https://70.153.18.130` → **Security Events**
- Filter rule group: `web` atau `syscheck`
- Pastikan alert dengan level ≥ 7 muncul

### 2. Cek Log Active Response (VM 1)

```bash
sudo tail -f /var/ossec/logs/active-responses.log
```

Output yang diharapkan:
```
firewall-drop add - <IP_ATTACKER> 1234 31151
```

### 3. Verifikasi IP Terblokir di Firewall (VM 2)

```bash
sudo iptables -L INPUT -n --line-numbers
```

Kalau berhasil diblokir:
```
Chain INPUT (policy ACCEPT)
num  target  prot  opt  source          destination
1    DROP    all   --   <IP_ATTACKER>   0.0.0.0/0
```

Cek spesifik IP:
```bash
sudo iptables -L INPUT -n | grep <IP_ATTACKER>
```

### 4. Cek Workflow n8n Terpicu

- Buka `http://70.153.18.130:5678`
- Workflow → klik **Executions**
- Setiap eksekusi menunjukkan langkah yang berhasil dijalankan

### 5. Test Koneksi dari Attacker (VM 3)

```bash
curl -v http://20.6.95.104/
# Expected: connection timeout

ping 20.6.95.104
# Expected: 100% packet loss
```

### Cara Unblock IP (Reset untuk Testing Ulang)

```bash
# Di VM 2
sudo iptables -L INPUT -n --line-numbers
sudo iptables -D INPUT <nomor_rule>

# Atau langsung berdasarkan IP
sudo iptables -D INPUT -s <IP_ATTACKER> -j DROP
```

---

## Struktur Direktori

```
/var/ossec/etc/
├── ossec.conf              # Konfigurasi Wazuh + Active Response + integrasi n8n
└── rules/
    └── local_rules.xml     # Custom rules (opsional)

/var/ossec/logs/
├── alerts/alerts.log       # Log semua alert
└── active-responses.log    # Log IP yang diblokir Active Response
```

---

## Troubleshooting

| Masalah | Penyebab | Solusi |
|---|---|---|
| `Permission denied` saat docker run | User tidak di grup docker | `sudo usermod -aG docker $USER && newgrp docker` |
| SSH putus setelah Docker jalan | Docker reset iptables | `sudo iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT` |
| Active Response tidak memblokir | Level rule terlalu tinggi | Turunkan `<level>` di ossec.conf atau cek rule ID |
| Alert tidak masuk ke n8n | Webhook tidak aktif | Pastikan workflow n8n di-toggle **Active** |
| n8n tidak bisa diakses | Port 5678 belum dibuka | Buka di Azure NSG + `iptables -I INPUT -p tcp --dport 5678 -j ACCEPT` |
| Wazuh manager gagal restart | Syntax error ossec.conf | `sudo /var/ossec/bin/wazuh-logtest` untuk cek config |

---

## 📚 Referensi

- [Wazuh Official Documentation](https://documentation.wazuh.com)
- [Wazuh Active Response](https://documentation.wazuh.com/current/user-manual/capabilities/active-response/)
- [n8n Documentation](https://docs.n8n.io)
- [n8n Docker Install](https://docs.n8n.io/hosting/installation/docker/)
- [Wazuh API Reference](https://documentation.wazuh.com/current/user-manual/api/reference.html)

---

