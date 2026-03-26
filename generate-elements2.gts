import { CardDef } from 'https://cardstack.com/base/card-api';
import { Component } from 'https://cardstack.com/base/card-api';
export class GenerateElements2 extends CardDef {
  static displayName = "generate-elements2";

  static isolated = class Isolated extends Component<typeof this> {
    <template>
    <!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Generate Elements</title>
<style>
table {
border-collapse: collapse;
width: 30%;
margin: 10px;
}

th, td {
border: 1px solid black;
padding: 8px;
text-align: left;
}

a {
color: blue;
}

img {
width: 30%;
}

</style>
</head>
<body>
<h1>Generate Elements</h1>
<textarea id="inputText" rows="10" cols="80" placeholder="Paste the content here"></textarea>
<br>
<button onclick="generateElements()">Generate Elements</button>
<button onclick="runCode()">Run Code</button>
<button id="imgBigSmallbutton" onclick="toggleImageBigSmall()">Make Image Big</button>
<button onclick="convertLinks()">Convert Links</button>
<button onclick="saveAsFile()">Save as HTML</button>
<button onclick="refreshAll()">Refresh Images and Videos</button>
<button onclick="clearErrors()">Clear Errors</button>
<div id="tableout"></div>
<div id="output"></div>

<div id='errordump'>ERROR DUMP</div>
<p></p><nav style="position: fixed; bottom: 0px; right: 0px;"><a href="#top">Top</a></nav>
<script>
var imgSizeNow = 'small';
function generateElements() {
output.innerHTML = inputText.value
//tableout.innerHTML = ''
//elements = ['div', 'a', 'img', 'video'];
//elements.forEach((element) => {
//selectedElements = output.querySelectorAll(element);
//if (selectedElements.length > 0) {
//table = document.createElement('table');
//headerRow = document.createElement('tr');
//headerRow.innerHTML = '<th>Index</th><th>' + element + '</th>';
//table.appendChild(headerRow);
//selectedElements.forEach((el, index) => {
//row = document.createElement('tr');
//cellIndex = document.createElement('td');
//cellValue = document.createElement('td');
//cellIndex.textContent = index + 1;
//if (element === 'a') {
//link = document.createElement('a');
//link.href = el.href;
//link.textContent = el.href;
//cellValue.appendChild(link);
//} else if (element === 'img' || element === 'video') {
//link = document.createElement('a');
//link.href = el.src;
//link.textContent = el.src;
//cellValue.appendChild(link);
//} else {
//link = document.createElement('a');
//link.href = '#' + el.innerText;
//link.textContent = el.innerText;
//cellValue.appendChild(link);
//}
//row.appendChild(cellIndex);
//row.appendChild(cellValue);
//table.appendChild(row);
//});
//tableout.appendChild(table);
//}
//});

}


function runCode() {
eval(inputText.value)
}


function toggleImageBigSmall(){
if (imgSizeNow == 'small') {
document.styleSheets[0].deleteRule(3);
imgSizeNow = 'big';
imgBigSmallbutton.textContent = "Make Image Small"
} else if (imgSizeNow == 'big') {
document.styleSheets[0].insertRule('img { width: 30%; }',3);
imgSizeNow = 'small';
imgBigSmallbutton.textContent = "Make Image Big"
}
}

function refreshAll(){
document.querySelectorAll('img').forEach(function(item){item.src = item.src})
document.querySelectorAll('video').forEach(function(item){item.src = item.src})
}

function clearErrors() {
for (var i = document.getElementsByClassName('none').length-1; i > -1; i--) {
errordump.append(document.getElementsByClassName('none')[i])
}
for (var i = document.getElementsByTagName('img').length-1; i > -1; i--) {
if (document.getElementsByTagName('img')[i].naturalWidth === 0) {
errordump.append(document.getElementsByTagName('img')[i])
}
}
for (var i = document.getElementsByTagName('img').length-1; i > -1; i--) {
if (document.getElementsByTagName('img')[i].naturalWidth === 90 && document.getElementsByTagName('img')[i].naturalHeight === 122){
errordump.append(document.getElementsByTagName('img')[i])
}
}
for (var i = document.getElementsByTagName('video').length-1; i > -1; i--) {
if (document.getElementsByTagName('video')[i].error != null && document.getElementsByTagName('video')[i].error.toString() === "[object MediaError]") {
errordump.append(document.getElementsByTagName('video')[i])
}
}
}

function makeVid(ele){ele.src = prompt()}

function convertLinks() {
inputText = document.getElementById("inputText").value;
outputDiv = document.getElementById("output");
links = inputText.split('|');
outputDiv.innerHTML = '';
links.forEach(link => {
anchorTag = '<a href="' + link.trim() + '}">' + link.trim() + '</a><br>';
outputDiv.innerHTML += anchorTag;
});
}

function saveAsFile() {
outputContent = document.getElementById("output").innerHTML;
if (!outputContent) {
alert("There is no content to save!");
return;
}
now = new Date();
year = now.getFullYear();
month = String(now.getMonth() + 1).padStart(2, '0');
day = String(now.getDate()).padStart(2, '0');
defaultFileName = 'todays-link-' + year + month + day + '.html';

blob = new Blob([outputContent], { type: "text/html" });
link = document.createElement("a");
link.href = URL.createObjectURL(blob);
link.download = defaultFileName; // Default filename with editable option
link.click();
}

document.addEventListener("keydown", function(event){if(event.ctrlKey && event.key === "Enter"){generateElements()}})

</script>
</body>
</html>
    </template>
  }
}