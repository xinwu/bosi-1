#!/bin/bash -eux

# RPM runs as root and doesn't like source files owned by a random UID
OUTER_UID=$(stat -c '%u' /bosi)
OUTER_GID=$(stat -c '%g' /bosi)
trap "chown -R $OUTER_UID:$OUTER_GID /bosi" EXIT
chown -R root:root /bosi

cd /bosi
git config --global user.name "Big Switch Networks"
git config --global user.email "support@bigswitch.com"

CURR_VERSION=$(awk '/^version/{print $3}' setup.cfg)

echo 'CURR_VERSION=' $CURR_VERSION
git tag -f -s $CURR_VERSION -m $CURR_VERSION -u "Big Switch Networks"

python setup.py sdist

# force success. but always check if pip install fails
twine upload dist/* -r pypi -s -i "Big Switch Networks" || true
# delay of 5 seconds
sleep 5
sudo -H pip install --upgrade bosi==$CURR_VERSION
if [ "$?" -eq "0" ]
then
  echo "PYPI upload successful."
else
  echo "PYPI upload FAILED. Check the logs."
fi
# remove the package
sudo -H pip uninstall -y bosi

# Prepare packages for rsync
OUTDIR=$(readlink -m "/bosi/dist/$GIT_BRANCH/$CURR_VERSION")
rm -rf "$OUTDIR" && mkdir -p "$OUTDIR"
mv /bosi/dist/*.tar.gz "$OUTDIR"
mv /bosi/dist/*.tar.gz.asc "$OUTDIR"
cp /bosi/bosi/scripts/* "$OUTDIR"
git log > "$OUTDIR/gitlog.txt"
touch "$OUTDIR/build-$CURR_VERSION"
ln -snf $(basename $OUTDIR) $OUTDIR/../latest

# revert the permissions
chown -R $OUTER_UID:$OUTER_GID /bosi
