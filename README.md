# react-native-lite-fs

### Install

```
npm install --save react-native-lite-fs
```

### API

```
type Callback = (error: Error, result: any)=> any;
type Path = string;
type Content = Buffer | string | ArrayBuffer;
```

##### `exists` (p: Path)=> Promise<number>

  * 0 不存在
  * 1 文件夹
  * 2 文件

##### `stat` (p: Path)=> Promise<{length: number, ctime: number, mtime: number, flag: number}>

  Android 中没有 ctime;

##### `mkdir` (p: Path, auto: boolean = false)=> Promise


##### `touch` (p: Path, auto: bool)=> Promise


##### `readir` (p: Path)=> Promise


##### `copy` (src: Path, to: Path)=> Promise


##### `move` (src: Path, to: Path=> Promise


##### `remove` (item: Path)=> Promise


##### `writeFile` (p: Path, content: Content)=> Promise<number>

  返回写入的字节数

##### `readFile` (p: Path)=> Promise<Buffer>


##### `open` (p: Path)=> Promise<File>


#### `File`

##### `close` ()=> Promise


##### `tell` ()=> Promise<number>


##### `seek` (offset = 0, )=> Promise<number>


##### `read` (length: number = DEFAULT_BUFFER_LENGTH, )=> Promise<Buffer>


##### `write` (content: Content, )=> Promise<number>


##### `truncate` (length: number, )=> Promise<number>




