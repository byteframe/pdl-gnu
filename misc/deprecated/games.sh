SRC=/home/byteframe/150_GB_SATA_25
DST=/run/media/byteframe/Games
unset UNKNOWN
find ${SRC}/ -maxdepth 2 -type f -iname "*.rar" -or -iname "*.zip" -or -iname "*.7z" \
  | grep -v __UNPLAYED > ${SRC}/filelist.tmp
while read FILE; do
  FILE="${FILE/${SRC}\//}"
  DIR="${FILE%\/*}"
  FILE="${FILE##*\/}"
  mkdir -p "${DST}/${DIR}"
  if [ ! -e "${DST}"/"${DIR}"/"${FILE}" ] ; then
    cp -v "${SRC}/${DIR}/${FILE}" "${DST}/${DIR}/${FILE}"
  fi
  mkdir -p "${DST}/${DIR}/${FILE%.*}"
  if [ ${FILE##*.} = "rar" ]; then
    COMMAND="unrar x"
  elif [ ${FILE##*.} = "zip" ]; then
    COMMAND="unzip"
  elif [ ${FILE##*.} = "7z" ]; then
    COMMAND="7z x"
  else
    UNKNOWN="${UNKNOWN}___${FILE}"
    echo "UNKNOWN FILE TYPE: ${FILE}"
    continue
  fi
  cd "${DST}/${DIR}/${FILE%.*}"
  echo "extracting: ${FILE}"
  ${COMMAND} "${DST}/${DIR}/${FILE}"
done < ${SRC}/filelist.tmp