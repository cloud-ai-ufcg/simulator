import matplotlib.pyplot as plt
from pathlib import Path
from matplotlib.image import imread

def show_behavior(directory_path):
    """
    Exibe todos os arquivos PNG contidos no diretório fornecido.

    Parâmetros:
        directory_path (str ou Path): Caminho para o diretório contendo os PNGs.
    """
    directory_path = Path(directory_path)

    if not directory_path.exists() or not directory_path.is_dir():
        raise ValueError(f"O caminho fornecido não existe ou não é um diretório: {directory_path}")

    # Lista todos os arquivos .png do diretório
    png_files = sorted(directory_path.glob("*.png"))
    if not png_files:
        print(f"⚠️ Nenhum arquivo PNG encontrado em {directory_path}")
        return

    for png_path in png_files:
        img = imread(str(png_path))
        plt.figure(figsize=(12, 6))
        plt.imshow(img)
        plt.axis("off")
        plt.title(png_path.name)
        plt.show()


if __name__ == "__main__":
    ROOT = Path(__file__).resolve().parent
    TEST_DIR = ROOT / "output"
    show_behavior(TEST_DIR)
