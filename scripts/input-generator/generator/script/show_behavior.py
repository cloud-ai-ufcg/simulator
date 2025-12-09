import matplotlib.pyplot as plt
from pathlib import Path
from matplotlib.image import imread

def show_behavior(directory_path):
    """
    Show all PNG files in the provided directory.

    Parameters:
       directory_path (str or Path): Path to the directory containing the PNGs.
    """
    directory_path = Path(directory_path)

    if not directory_path.exists() or not directory_path.is_dir():
        raise ValueError(f"The provided path does not exist or is not a directory: {directory_path}")

    # List all .png files in the directory
    png_files = sorted(directory_path.glob("*.png"))
    if not png_files:
        print(f"⚠️ No PNG files found in {directory_path}")
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
