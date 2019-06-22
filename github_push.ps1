# push to github with commit message

param ($msg = $args[0])
if (([string]::IsNullOrEmpty($msg)))
{
    throw "Error: no any commit msg..."
}

git add *
git commit -m $msg
git push origin hexo