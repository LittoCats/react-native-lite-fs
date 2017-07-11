package com.littocats.filesystem;

import android.content.Context;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.telephony.TelephonyManager;
import android.util.Log;

import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableNativeMap;
import com.facebook.react.bridge.WritableNativeArray;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.nio.channels.FileChannel;
import java.util.HashMap;
import java.util.Map;

import javax.annotation.Nullable;

/**
 * Created by Dragon-Li on 5/9/17.
 */

public class FSModule extends ReactContextBaseJavaModule {

    static char HexDetable[] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8,9,0,0,0,0,0,0,0,10,11,12,13,14,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,10,11,12,13,14,15};
    static char HexTable[] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'};

    Map<Integer, RandomAccessFile> m_files = new HashMap<>();

    public FSModule(ReactApplicationContext reactContext) {
        super(reactContext);
    }

    @Override
    protected void finalize() throws Throwable {
        for (RandomAccessFile file: m_files.values()) {
            file.close();
        }
        super.finalize();
    }

    @Override
    public String getName() {
        return "LiteFileSystem";
    }

    @Nullable
    @Override
    public Map<String, Object> getConstants() {
        Map<String, Object> consts = new HashMap<>();
        consts.put("HOME", getReactApplicationContext().getExternalFilesDir(null).getAbsolutePath());
        consts.put("TEMP", getReactApplicationContext().getExternalCacheDir().getAbsolutePath());
        consts.put("UUID", UDID.getUDID(getReactApplicationContext()));
        consts.put("MODEL", Build.MODEL);
        return consts;
    }


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

     ******************************************************************************/

    @ReactMethod
    public void open(String path, Promise promise) {
        try {
            RandomAccessFile file = new RandomAccessFile(path, "rw");
            int fd = file.hashCode();
            m_files.put(fd, file);
            promise.resolve(fd);
        } catch (FileNotFoundException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void close(Integer fd, Promise promise) {
        RandomAccessFile file = m_files.get(fd);
        try {
            file.close();
            promise.resolve(null);
        } catch (IOException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void tell(Integer fd, Promise promise) {
        RandomAccessFile file = m_files.get(fd);

        try {
            int tell = (int)file.getFilePointer();
            promise.resolve(tell);
        } catch (IOException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void seek(Integer fd, Integer offset, Promise promise) {
        RandomAccessFile file = m_files.get(fd);

        try {
            file.seek(offset);
            promise.resolve(offset);
        } catch (IOException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void truncate(Integer fd, Integer length, Promise promise) {
        RandomAccessFile file = m_files.get(fd);

        try {
            FileChannel channel = file.getChannel();
            channel.position(length);
            promise.resolve(length);
        } catch (IOException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void read(Integer fd, int length, Promise promise) {
        try {
            RandomAccessFile file = m_files.get(fd);
            byte[] bytes = new byte[length];
            length = file.read(bytes, 0, length);
            StringBuffer sb = new StringBuffer();
            int index = 0;
            while (index < length) {
                int b = bytes[index++];
                sb.append(HexTable[(b >> 4) & 0xf]);
                sb.append(HexTable[b & 0xf]);
            }
            promise.resolve(sb.toString());
        } catch (IOException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void write(Integer fd, String hex, Promise promise) {
        RandomAccessFile file = m_files.get(fd);
        try {
            byte[] bytes = new byte[hex.length()/2];
            int index = 0;
            while (index < hex.length()) {
                char h = HexDetable[hex.charAt(index++)];
                char l = HexDetable[hex.charAt(index++)];
                bytes[index/2-1] = (byte) (((h << 4) & 0xf0) | (l & 0xf));
            }

            file.write(bytes, 0, hex.length()/2);

            promise.resolve(hex.length()/2);
        }catch (IOException e) {
            promise.reject(e);
        }
    }


    @ReactMethod
    public void stat(String path, Promise promise) {
        File file = new File(path);
        WritableMap wm = new WritableNativeMap();
        wm.putInt("flag", file.isFile() ? 2 : file.isDirectory() ? 1 : -1);
        wm.putDouble("length", file.length());
        wm.putDouble("mtime", file.lastModified());
        promise.resolve(wm);
    }

    @ReactMethod
    public void exists(String path, Promise promise) {
        File file = new File(path);
        promise.resolve(!file.exists() ? 0 : file.isDirectory() ? 1 : file.isFile() ? 2 : 0);
    }


    @ReactMethod
    private void readir(String path, Promise promise) {
        File file = new File(path);
        if (!file.isDirectory()) return;
        File items[] = file.listFiles();
        WritableArray array = new WritableNativeArray();
        for (File item : items) {
            array.pushString(item.getPath());
        }
        promise.resolve(array);
    }

    @ReactMethod
    public void remove(String path, Promise promise) {
        remove(new File(path));
        promise.resolve(null);
    }

    @ReactMethod
    public void move(String src, String to, Promise promise) {
        File file = new File(src);
        boolean success = file.renameTo(new File(to));
        if (success) {
            promise.resolve(true);
        }else{
            promise.reject("" + success, "move file fail.");
        }
    }

    @ReactMethod
    public void copy(String src, String to, Promise promise) {
        FileInputStream is = null;
        FileOutputStream os = null;
        int byteread = 0;
        try {
            is = new FileInputStream(src);
            os = new FileOutputStream(to);

            byte[] buffer = new byte[4096];

            while ((byteread = is.read(buffer)) != -1) {
                os.write(buffer, 0, byteread);
            }

            promise.resolve(true);

        } catch (FileNotFoundException e) {
            promise.reject(e);
        } catch (IOException e) {
            promise.reject(e);
        } finally {
            try {
                if (is != null) is.close();
                if (os != null) os.close();
            } catch (IOException e) {
                e.printStackTrace();
            }
        }
    }

    @ReactMethod
    public void touch(String path, Promise promise) {
        File file = new File(path);
        try {
            promise.resolve(file.createNewFile());
        } catch (IOException e) {
            promise.reject(e);
        }
    }

    @ReactMethod
    public void mkdir(String path, Promise promise) {
        File file = new File(path);
        promise.resolve(file.mkdir());
    }


    private void remove(File file) {
        if (file.isFile()) {
            file.deleteOnExit();
        }else if (file.isDirectory()){
            File files[] = file.listFiles();
            for (File f: files) {
                remove(f);
            }
        }
    }

    private String getUUID() {
        return "";
    }
}