#!/bin/bash

# Finds every video file in this folder recursively and converts it to a new, efficient, VP9+OPUS video.

# Optional parameter to skip encoding a certain number of videos
start=0
if [ $# -gt 0 ]; then
	start="$1"
fi

index="$start"

readarray -d '' files < <(find . -type f -regextype posix-extended -regex '^.*\.(mkv|mp4|mov|avi)$' -print0)

get_info() {
	skip=0
	# Find the default video track
	info=$(ffmpeg -i "$file" 2>&1 | grep 'Video:.*\(default\)')
	# Find the codec, this occasionally fails but it's optional
	codec=$(echo "$info" | sed -nE 's/^.*Video: ([a-z0-9-]+).*$/\1/p')
	# Find the bit rate, VBR tracks do not have a bitrate so this is optional
	bitrate=$(echo "$info" | sed -nE 's/^.* ([0-9]+) kb\/s.*$/\1/p')
	# Find the frame height, this is critical to the function
	height=$(echo "$info" | sed -nE 's/^.*[0-9]{3}x([0-9]+).*$/\1/p')
	if [[ -n "$height" ]]; then
		echo "Video specs found. Codec: $codec, Bit rate: $bitrate, Height: $height"
	else
		echo "Failed to fetch video specs. Skipping this file."
		skip=1
		return 0
	fi
	# Decide what to do based on gathered information
	# First, implement recomended settings
	# This is based on https://developers.google.com/media/vp9/settings/vod
	# but I've reduced all the numbers with experimentation
	if [[ "$height" -gt 1500 ]]; then # 4K-ish video
		t_bitrate=6000
		t_quality=24
	elif [[ "$height" -gt 900 ]]; then # 2K-ish video
		t_bitrate=1700
		t_quality=32
	elif [[ "$height" -gt 600 ]]; then # HD video
		t_bitrate=850
		t_quality=33
	else # DVD video
		skip=1
		#echo "skip reason: dvd quality"
		return 0
	fi
	#second, check if these settings will save space in practice
	if [[ -n "$bitrate" ]] && [[ "$bitrate" -lt "$t_bitrate" ]]; then
		# this will likely take up a similar amount of space compared to the original
		skip=1
		#echo "skip reason: bitrate"
		return 0
	elif [[ "$codec" == "vp9" ]]; then
		# don't transcode videos that are already using VP9, trust that they were encoded efficiently from the start
		skip=1
		#echo "skip reason: vp9"
		# you may want to override this
		return 0
	elif [[ "$codec" == "hevc" ]]; then
		# don't transcode videos that are encoded with H.265, this format is technically more space efficient
		skip=1
		#echo "skip reason: hevc"
		# you may want to override this
		return 0
	fi
}

process_file() {
	echo
	echo "=========================================="
        echo "Processing file $index... ($file)"

	# Skip transcoding files with a marker in the name
	if [[ "$file" =~ recode\.mkv$ ]]; then
		echo "This is the already transcoded file, skipping..."
		return 0
	fi

	# Get file metadata via ffmpeg and generate recommended settings
	get_info
	echo "Quality recommendation determined. Bit rate: $t_bitrate, CRF: $t_quality, Skip: $skip"

	# If get_info returns skip=1, this means the recommended route is to not transcode
	if [[ "$skip" == 1 ]]; then
		echo "Compression will not save size, skipping..."
		return 0
	fi

	newfile="${file%.*}.recode.mkv"
	if ! [[ -f "$newfile" ]]; then
		ffmpeg -v quiet -stats -i "$file" -pass 1 -map 0 -vcodec libvpx-vp9 -deadline good -speed 4 -b:v "$t_bitrate"K -an -sn -f null /dev/null && \
		ffmpeg -v quiet -stats -i "$file" -pass 2 -map 0 -vcodec libvpx-vp9 -deadline good -speed 2 -b:v "$t_bitrate"K -pass 2 -acodec libopus -b:a 128K -scodec copy -crf "$t_quality" "$newfile"
	else
		echo "This file has already been transcoded, skipping..."
		return 0
	fi
}

echo "Starting at $start..."
len=${#files[@]}
len=$((len - start))
for i in $(seq $len); do
	file=${files["$i"]}
	process_file "$file"
	index=$((index + 1))
done
