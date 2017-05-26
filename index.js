import {
  NativeModules
} from 'react-native';

import invariant from 'invariant';
import {Buffer} from 'buffer';

import path from 'react-native-path';
import enqueue from 'react-native-lite-enqueue';

type Callback = (error: Error, result: any)=> any;
type Path = string;
type Content = Buffer | string | ArrayBuffer;

const Native = NativeModules.LiteFileSystem;

/*******************************************************************************

  Native.open     = (path: string)=> number // fd
  Native.tell     = (fd: number, location: number)=> number // current location
  Native.seek     = (fd: number, offset: number)=> number // current location
  Native.truncate = (fd: number, length: number)=> number // of file length
  Native.write    = (fd: number, hex: string, offset: number)=> number // of bytes has been written
  Native.read     = (fd: number, length: number)=> string // encoded hex
  Native.close    = (fd: number)=> undefined

  Native.exists   = (file: string)=> number // 0 not exists, 1 directory, 2 regular file
  Native.remove   = (file: string)=> undefined
  Native.move     = (file: string)=> undefined
  Native.copy     = (file: string)=> undefined
  Native.readir   = (file: string)=> Array<string>
  Native.touch    = (file: string)=> undefined
  Native.mkdir    = (file: stirng)=> undefined
  Native.stat     = (file: stat)=> Object<{path: string, length: number, ctime: number, mtime: number, flag: number}>

/******************************************************************************/

const {HOME, TEMP} = Native;
const MAX_BUFFER_LENGTH = Math.pow(2, 20); // 1M
const DEFAULT_BUFFER_LENGTH = Math.pow(2, 10) * 4; // 4K

const fs = module.exports = exports = {
  HOME, TEMP,

  /**
   *  检查文件是否存在
   *  response: 0 | 1 | 2
   *  0 不存在
   *  1 目录
   *  2 文件
   */
  exists(p: Path, callback: Callback) {
    invariantPath(p);
    return normalize(Native.exists(p), callback)
  },

  stat(p: Path, callback: Callback) {
    invariantPath(p);
    return normalize(Native.stat(p).then(statctor), callback)
  },

  /**
   *  @param auto 是否自动创建父目录
   */
  mkdir(p: Path, auto: boolean = false, callback: Callback) {
    invariantPath(p);
    if (typeof auto === 'function') {
      callback = auto;
      auto = false;
    }

    return normalize(Native.exists(p).then(function(stat) {
      if (stat === 2) throw new Error('regular file already exists.');
      if (stat === 1) return 1;
      return fs.mkdir(path.dirname(p), auto).then(function (stat) {
        if (!stat) throw new Error('mkdir error.');
        return Native.mkdir(p);
      });
    }), callback);
  },

  touch(p: Path, auto: bool, callback: Callback) {
    invariantPath(p);
    if (typeof auto === 'function') {
      callback = auto;
      auto = false;
    }
    const dirname = path.dirname(p);
    return normalize(Native.exists(p).then(function (stat) {
      if (stat !== 0) throw new Error('file already exists.');
      return Native.exists(dirname)
    }).then(function(stat){
      if (stat === 2) throw new Error(`${dirname} is not a directory.`);
      if (stat === 0 && !auto) throw new Error(`${dirname} dose not exists.`); 
      if (stat === 0) return fs.mkdir(dirname, auto);
    }).then(function(stat) {
      return Native.touch(p);
    }), callback);
  },

  readir(p: Path, callback: Callback) {
    invariantPath(p);
    return normalize(Native.exists(p).then(function(stat) {
      if (stat === 0) throw new Error('file not exists');
      if (stat === 2) throw new Error('not directory.');
      return Native.readir(p)
    }), callback);
  },

  copy(src: Path, to: Path, callback: Callback) {
    invariantPath(src, to);
    return normalize(Native.exists(src).then(function(stat) {
      if (stat === 0) throw new Error(`file not exists: ${src}`);
      return Native.exists(to);
    }).then(function (stat) {
      if (stat !== 0) throw new Error(`file already exists: ${to}`);
      return Native.copy(src, to);
    }), callback);
  },

  move(src: Path, to: Path, callback: Callback){
    invariantPath(src, to);
    return normalize(Native.exists(src).then(function(stat) {
      if (stat === 0) throw new Error(`file not exists: ${src}`);
      return Native.exists(to);
    }).then(function (stat) {
      if (stat !== 0) throw new Error(`file already exists: ${to}`);
      return Native.move(src, to);
    }), callback);
  },

  remove(item: Path, callback: Callback) {
    invariantPath(item);
    return normalize(Native.exists(item).then(function(stat) {
      if (stat === 0) return stat;
      return Native.remove(item);
    }), callback);
  },

  writeFile(p: Path, content: Content, callback: Callback) {
    invariantPath(p);
    return normalize(Native.exists(p).then(function(stat) {
      if (stat === 1) throw new Error('not regular file.');
      if (stat === 0) return Native.touch(p);
    }).then(async function() {
      const file = await fs.open(p);

      try {
        return await file.write(content)
      }finally{
        file.close();
      }
      
    }), callback);
  },

  readFile(p: Path, callback: Callback) {
    invariantPath(p);
    return normalize(Native.exists(p).then(function (stat) {
      if (stat === 0) throw new Error('file not exists');
      if (stat === 1) throw new Error('not regular file.');
      // return Native.read(p, 0 /*offset*/, MAX_BUFFER_LENGTH, /*MaxLength 最大只能支持 2^20 1M 的文件，其它的可以分步读取*/)
    }).then(async function() {
      const file = await fs.open(p);
      
      try {
        const bufs = [];
        while(true) {
          buf = await file.read();
          if (buf.length) {
            bufs.push(buf);
          }else{
            break;
          }
        }
        return Buffer.concat(bufs)
      }finally{
        file.close();  
      }
    }).then(bufferctor), callback)
  },

  open(p: Path, callback: Callback) {
    invariantPath(p);
    return normalize(Native.exists(p).then(function(stat){
      if (stat === 0) throw new Error('file not exists: ' + p);
      if (stat === 1) throw new Error('not regular file: ' + p);
      return new File(p).open();
    }), callback);
  }
}

class File {
  constructor(path) {
    this.__path = path;
  }

  get path() {
    return this.__path;
  }

  get fd() {
    if (typeof this.__fd !== 'number') throw new Error('File has been closed.');
    return this.__fd;
  }

  open(callback: Callback) {
    return enqueue(this, ()=>{
      if (this.__fd) return Promise.resolve(this);
      return normalize(Native.open(this.__path).then((fd)=> {
        this.__fd = fd;
        return this;
      }), callback)
    })
  }
  close(callback: Callback) {
    return enqueue(this, ()=>{
      if (!this.__fd) return Promise.resolve();
      return normalize(Native.close(this.fd).then(()=>{
        delete this.__fd;
      }), callback)
    });
  }

  tell(callback: Callback) {
    return enqueue(this, ()=>normalize(Native.tell(this.fd), callback));
  }
  seek(offset = 0, callback: Callback) {
    return enqueue(this, ()=>normalize(Native.seek(this.fd, offset), callback));
  }
  read(length: number = DEFAULT_BUFFER_LENGTH, callback: Callback) {
    return enqueue(this, ()=>normalize(Native.read(this.fd, length).then(bufferctor), callback));
  }
  write(content: Content, callback: Callback) {
    return enqueue(this, ()=>normalize(Native.write(this.fd, Buffer.from(content).toString('hex')), callback));
  }
  truncate(length: number, callback: Callback) {
    return enqueue(this, ()=>normalize(Native.truncate(this.fd, length), callback));
  }
  stat(callback: Callback) {
    return enqueue(this, ()=>normalize(Native.stat(this.path).then(statctor), callback));
  }
}

class Stat {
  constructor(stat) {
    for (var prop of Object.keys(stat)) {
      this[prop] = stat[prop];
    }
    
    this.ctime = new Date(stat.ctime);
    this.mtime = new Date(stat.mtime);
  }

  isFile() {
    return this._flag === 2;
  }
}

function statctor(src: Object) {
  return src;
}

function bufferctor(hex) {
  return Buffer.from(hex, 'hex');
}

function invariantPath(... paths) {
  for (var path of paths) {
    invariant(typeof path === 'string' && path[0] === '/', `Path must be absolute file path string, recieved: ${path}`)
  }
}

function normalize(promise, callback) {
  if (typeof callback !== 'function') return promise;
  promise.then(resolve).catch(reject);

  function resolve(res) {
    callback(undefined, res);
  }

  function reject(err) {
    callback(err, undefined);
  }
}