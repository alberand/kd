local -a patchesArray
patchesArray=( ${patches[@]:-} )
for p in "${patchesArray[@]}"; do
  echo "applying patch $p"
  patch -p1 < $p
done
