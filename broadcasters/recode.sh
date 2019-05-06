# concat audio
# ffmpeg -f concat -i 1.txt -c copy 1+2.ogg
ffmpeg \
	-re \
	-v info \
	-i ${MEDIA_FILE} \
	-map 0:a:0 \
	-acodec libopus -ab 128k -ac 2 -ar 48000 \
	-map 0:v:0 \
	-pix_fmt yuv420p -c:v libvpx -b:v 1000k -deadline realtime -cpu-used 8 \
	${OUT_FILE}