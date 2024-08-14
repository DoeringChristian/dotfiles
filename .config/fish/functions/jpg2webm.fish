function jpg2webm --wraps='ffmpeg -r 30 -i %d.jpg output.webm' --description 'alias jpg2webm=ffmpeg -r 30 -i %d.jpg output.webm'
    ffmpeg -r 30 -i %d.jpg output.webm $argv
end
