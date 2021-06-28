#include <iostream>
#include <Windows.h>
#include <fstream>
#include <vector>
#include <chrono> 
#include <iomanip> 
#include <thread>
#include <mutex>
#include <string.h>

using namespace std;

void scan_cpu(unsigned char *byte_file, unsigned char *sign, int sign_size, int part_size, int file_size, char *mask, int tread_id)
{
    int offset = tread_id * part_size; // вычисление сдвига по файлу
    int sign_shift = 0;
    while ((sign_shift <= part_size) && (offset + sign_shift < file_size - sign_size)) { // цикл алгоритма с учетом перекрытий
        bool sign_check = true;
        for (int i = 0; i < sign_size; i++)
        {
            if (byte_file[offset + sign_shift + i] != sign[i])
            {
                if (mask[i] == '1') // проверяем, является ли байт ключевым
                {
                    sign_check = false;
                    break;
                }
                else
                {
                    continue;
                }
            }
        }
        if (sign_check == true)
        {
            /* сигнатура найдена */
            //printf("sign found on address:  %04x\n", (offset + sign_shift));
        }
        sign_shift++;
    }
}
int main()
{
    printf("direct search algoritm on CPU\n");
    /* процесс считывания данных */
    const char* filename = "D:/_Politech/ScanSignature/RealtekHDAudio_Rus_Setup.exe"; // используется EXE звукового драйвера, т.к. самый большой найденный EXE
    ifstream file; // файл открывается для бинарного считывания 
    file.open(filename, ios_base::binary);
    file.seekg(0, ios::end); // определение длины файла
    size_t fileSize = file.tellg();
    file.seekg(0, ios::beg);
    vector<byte> byte_file(fileSize, 0); // создание вектора, в котором будут хранится все байты из файла 
    file.read(reinterpret_cast<char*>(&byte_file[0]), fileSize); // считывание    
    file.close(); // файл закрывается

    vector<unsigned char> sign_buffer = { 0x80, 0x3E, 0x00, 0x0F };
    char mask_[20] = "111111";
    int sign_size = sign_buffer.size();
    int file_size = byte_file.size();
    
    auto start = chrono::high_resolution_clock::now(); // замер времени для инициализации
    /* запись файла в память ЦПУ */
    unsigned char *bytefile = new unsigned char[file_size];
    for (int i = 0; i < file_size; i++) {
        bytefile[i] = byte_file[i];
    }
    /* запись сигнатуры в память ЦПУ */
    unsigned char *sign = new unsigned char[sign_size];
    for (int i = 0; i < sign_size; i++) {
        sign[i] = sign_buffer[i];
    }
    /* запись маски в память ЦПУ */
    char *mask = new char[20];
    for (int i = 0; i < sign_size; i++) {
        mask[i] = mask_[i];
    }
    auto stop = chrono::high_resolution_clock::now();
    auto duration = chrono::duration_cast<chrono::milliseconds>(stop - start);
    printf("sign: %s\nmask: %s\n", sign, mask);
    printf("initialising time: %d milliseconds.\n", duration.count());

    /* инициализация параметров */
    int treads[6] = { 2, 4, 8, 16, 32 }; // массив с количеством потоков для каждого выполнения бенчмарка
    int threads_ = 0; 
    for (int i = 0; i < 5; i++) 
    {
        threads_ = treads[i];
        thread* threads = new thread[threads_];
        int part_size = file_size / threads_;
        int thread_counter = 0;
        auto start = chrono::high_resolution_clock::now();
        for (int i = 0; i < threads_; i++) {
            threads[i] = thread(scan_cpu, bytefile, sign, sign_size, part_size, file_size, mask, i); // вызов функции на CPU 
            thread_counter++;
        }
        for (int i = 0; i < thread_counter; i++) {
            threads[i].join();
        }
        auto stop = chrono::high_resolution_clock::now();
        auto duration = chrono::duration_cast<chrono::milliseconds>(stop - start);
        printf("for %d treads execution time: %d milliseconds.\n", threads_, duration.count());
    }

    /* освобождение памяти */
    delete[] bytefile;
    delete[] sign;
    delete[] mask;
    cout << "\npress enter for exit";
    cin.ignore();
}

