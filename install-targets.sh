sudo tee /config/Targets > /dev/null <<'EOF'
*** Targets ***
probe = FPing
menu = Top
title = Network Latency Grapher
remark = Script by github.com/Kintoyyy.

+ Local
menu = Local
title = Local Network (ICMP)
++ LocalMachine
menu = Local Machine
title = This host
host = localhost

+ DNS
menu = DNS latency
title = DNS latency
probe = DNS
++ Google1
title = Google DNS 8.8.8.8
host = 8.8.8.8
++ Google2
title = Google DNS 8.8.4.4
host = 8.8.4.4
++ Cloudflare1
title = Cloudflare DNS 1.1.1.1
host = 1.1.1.1
++ Cloudflare2
title = Cloudflare DNS 1.0.0.1
host = 1.0.0.1
++ Quad9
title = Quad9 DNS
host = 9.9.9.9
++ OpenDNS
title = OpenDNS
host = 208.67.222.222

+ HTTP
menu = HTTP latency
title = HTTP latency (ICMP)
probe = FPing
++ Facebook
host = facebook.com
++ Youtube
host = youtube.com
++ TikTok
host = tiktok.com
++ Instagram
host = instagram.com
++ Gcash
host = m.gcash.com
++ Discord
host = discord.com
++ Google
host = google.com
++ Cloudflare
host = cloudflare.com
++ Amazon
host = amazon.com
++ Netflix
host = www.netflix.com

+ CDN
menu = CDN Providers
title = Major CDN Providers
probe = FPing
++ CloudflareSpeed
host = speed.cloudflare.com
++ FacebookCDN
host = static.xx.fbcdn.net
++ FacebookMobileCDN
host = z-m-static.xx.fbcdn.net
++ Fastly
host = global.ssl.fastly.net
++ Highwinds
host = hwcdn.net
++ CDN77
host = cdn77.com
++ SteamCDN
host = steamcdn-a.akamaihd.net

+ Cloud
menu = Cloud Services
title = Major Cloud Providers
probe = FPing
++ AWSS3
host = s3.amazonaws.com
++ AWSEC2
host = ec2.amazonaws.com
++ GCPCompute
host = compute.googleapis.com
++ DigitalOcean
host = digitaloceanspaces.com
++ Linode
host = linode.com
EOF
